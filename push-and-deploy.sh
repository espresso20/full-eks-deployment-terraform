#!/usr/bin/env bash
# push-and-deploy.sh — builds, pushes, and deploys an image to the EKS cluster.
#
# Usage:
#   ./push-and-deploy.sh                          # uses hello-server:latest, tag=latest
#   ./push-and-deploy.sh myimage:mytag            # custom local image
#   ./push-and-deploy.sh myimage:mytag v2.0       # custom local image + ECR tag
#
# All AWS config is read from terraform outputs — no hardcoded values.

set -euo pipefail

LOCAL_IMAGE="${1:-hello-server:latest}"
TAG="${2:-latest}"

# ── Read config from Terraform outputs ───────────────────────────────────────
if ! terraform output &>/dev/null; then
  echo "ERROR: No terraform outputs found. Run 'terraform apply' first." >&2
  exit 1
fi

PROFILE=$(terraform output -raw aws_profile)
REGION=$(terraform output  -raw aws_region)
ECR_URL=$(terraform output  -raw ecr_repository_url)
CLUSTER=$(terraform output  -raw cluster_name)
ACCOUNT=$(echo "$ECR_URL" | cut -d'.' -f1)

echo "==> Config loaded from terraform state"
echo "    Profile  : $PROFILE"
echo "    Region   : $REGION"
echo "    Cluster  : $CLUSTER"
echo "    ECR      : $ECR_URL"
echo ""

# ── SSO session check ─────────────────────────────────────────────────────────
if ! aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
  echo "==> SSO session expired — logging in..."
  aws sso login --profile "$PROFILE"
fi

# ── kubeconfig ────────────────────────────────────────────────────────────────
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" --profile "$PROFILE" 2>/dev/null

# ── Authenticate Docker with ECR ──────────────────────────────────────────────
echo "==> Authenticating Docker with ECR..."
aws ecr get-login-password --region "$REGION" --profile "$PROFILE" \
  | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

# ── Tag and push ───────────────────────────────────────────────────────────────
echo "==> Tagging ${LOCAL_IMAGE} -> ${ECR_URL}:${TAG}"
docker tag "$LOCAL_IMAGE" "${ECR_URL}:${TAG}"

echo "==> Pushing to ECR..."
docker push "${ECR_URL}:${TAG}"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo "==> Deploying to cluster..."

if kubectl get deployment hello-server &>/dev/null; then
  # Deployment exists — rolling update
  kubectl set image deployment/hello-server hello-server="${ECR_URL}:${TAG}"
  echo "==> Rolling update triggered."
else
  # First deploy — apply manifests then set the real image
  echo "==> First deploy — applying manifests..."
  kubectl apply -f k8s/hello-server/
  kubectl set image deployment/hello-server hello-server="${ECR_URL}:${TAG}"
fi

echo "==> Waiting for rollout..."
kubectl rollout status deployment/hello-server --timeout=180s

echo ""
echo "==> Done. External address (NLB may take 60-90s to become active):"
kubectl get svc hello-server
