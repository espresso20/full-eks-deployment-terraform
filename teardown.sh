#!/usr/bin/env bash
# teardown.sh — fully destroys the dev EKS stack in the correct order.
#
# Order matters:
#   1. Delete K8s LoadBalancer services  → deprovisions AWS NLBs/ELBs
#   2. Wait for ELBs to fully disappear  → so VPC ENIs are released
#   3. Delete PVCs                       → deprovisions EBS volumes
#   4. Run terraform destroy             → removes all remaining infrastructure

set -euo pipefail

PROFILE="aroffler-dev-admin-access"
REGION="us-east-1"
CLUSTER_NAME="dev-eks"
TF_VARS="terraform.tfvars"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BOLD}==>${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
fatal()   { echo -e "${RED}✗${NC} $*"; exit 1; }

# ── Confirmation ──────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}${BOLD}FULL STACK TEARDOWN${NC}"
echo "  Cluster : $CLUSTER_NAME"
echo "  Region  : $REGION"
echo "  Profile : $PROFILE"
echo ""
read -r -p "Type 'destroy' to confirm: " CONFIRM
[[ "$CONFIRM" == "destroy" ]] || fatal "Aborted."
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
for cmd in aws kubectl terraform; do
  command -v "$cmd" &>/dev/null || fatal "$cmd not found in PATH"
done

# ── SSO session check ─────────────────────────────────────────────────────────
info "Checking AWS SSO session..."
if ! aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
  warn "SSO session expired — logging in..."
  aws sso login --profile "$PROFILE"
fi
success "SSO session valid"

# ── Connect kubectl ───────────────────────────────────────────────────────────
info "Updating kubeconfig..."
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --profile "$PROFILE" &>/dev/null; then
  aws eks update-kubeconfig \
    --region "$REGION" \
    --name "$CLUSTER_NAME" \
    --profile "$PROFILE" 2>/dev/null
  KUBECTL_OK=true
else
  warn "EKS cluster not found — skipping kubectl steps (may already be destroyed)"
  KUBECTL_OK=false
fi

# ── Delete all LoadBalancer services (creates real AWS ELBs/NLBs) ─────────────
if [[ "$KUBECTL_OK" == "true" ]]; then
  info "Finding LoadBalancer services across all namespaces..."
  LB_SVCS=$(kubectl get svc --all-namespaces \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  if [[ -n "$LB_SVCS" ]]; then
    echo "$LB_SVCS" | while IFS='/' read -r NS SVC; do
      info "Deleting LoadBalancer service: $NS/$SVC"
      kubectl delete svc "$SVC" -n "$NS" --ignore-not-found
    done

    # Wait for AWS to actually deprovision the ELBs before proceeding.
    # Terraform destroy will fail if VPC ENIs are still attached.
    info "Waiting for AWS to deprovision load balancers (this can take 2-3 min)..."
    for i in $(seq 1 36); do  # 36 x 5s = 3 min max
      ELB_COUNT=$(aws elb describe-load-balancers \
        --profile "$PROFILE" --region "$REGION" \
        --query "length(LoadBalancerDescriptions[?contains(VPCId, '')])" \
        --output text 2>/dev/null || echo "0")
      NLB_COUNT=$(aws elbv2 describe-load-balancers \
        --profile "$PROFILE" --region "$REGION" \
        --query "length(LoadBalancers[?State.Code!='active' || State.Code=='active'])" \
        --output text 2>/dev/null || echo "0")

      # Simpler: just check if any ELB/NLB tags reference our cluster
      CLUSTER_ELBS=$(aws elbv2 describe-load-balancers \
        --profile "$PROFILE" --region "$REGION" \
        --query "LoadBalancers[*].LoadBalancerArn" \
        --output text 2>/dev/null || true)

      FOUND=0
      for ARN in $CLUSTER_ELBS; do
        TAGS=$(aws elbv2 describe-tags \
          --profile "$PROFILE" --region "$REGION" \
          --resource-arns "$ARN" \
          --query "TagDescriptions[0].Tags[?Key=='kubernetes.io/cluster/${CLUSTER_NAME}']" \
          --output text 2>/dev/null || true)
        [[ -n "$TAGS" ]] && FOUND=$((FOUND + 1))
      done

      [[ "$FOUND" -eq 0 ]] && break
      echo "  Still waiting for $FOUND load balancer(s) to deprovision... (${i}/36)"
      sleep 5
    done
    success "Load balancers deprovisioned"
  else
    success "No LoadBalancer services found"
  fi

  # ── Delete PVCs (releases EBS volumes so Terraform can clean up) ─────────────
  info "Deleting PersistentVolumeClaims..."
  PVC_COUNT=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$PVC_COUNT" -gt 0 ]]; then
    kubectl delete pvc --all --all-namespaces --ignore-not-found
    info "Waiting for EBS volumes to be released..."
    sleep 15
    success "PVCs deleted"
  else
    success "No PVCs found"
  fi

  # ── Delete app namespace resources ────────────────────────────────────────────
  info "Deleting application deployments and services..."
  kubectl delete deployment,service,ingress --all -n default --ignore-not-found 2>/dev/null || true
fi

# ── Terraform destroy ─────────────────────────────────────────────────────────
info "Running terraform destroy..."
terraform destroy -var-file="$TF_VARS" -auto-approve

echo ""
success "Teardown complete — all resources destroyed."
