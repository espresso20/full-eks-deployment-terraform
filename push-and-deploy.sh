#!/usr/bin/env bash
set -euo pipefail

PROFILE="aws-sso-profile"
REGION="us-east-1"
ACCOUNT="ACCOUNT-NUMBER"
REPO="hello-server"
ECR_URL="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}"
LOCAL_IMAGE="${1:-hello-server:latest}"
TAG="${2:-remediated}"

echo "==> Authenticating Docker with ECR..."
aws ecr get-login-password --region "$REGION" --profile "$PROFILE" \
  | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> Tagging ${LOCAL_IMAGE} -> ${ECR_URL}:${TAG}"
docker tag "$LOCAL_IMAGE" "${ECR_URL}:${TAG}"

echo "==> Pushing to ECR..."
docker push "${ECR_URL}:${TAG}"

echo "==> Updating deployment image..."
kubectl set image deployment/hello-server \
  hello-server="${ECR_URL}:${TAG}" \
  --record 2>/dev/null || true

# If deployment doesn't exist yet, apply the manifests
if ! kubectl get deployment hello-server &>/dev/null; then
  echo "==> Deployment not found — applying manifests..."
  kubectl apply -f k8s/hello-server/
else
  echo "==> Rolling update triggered."
fi

echo "==> Waiting for rollout..."
kubectl rollout status deployment/hello-server --timeout=120s

echo ""
echo "==> Done. Fetching external address (may take 1-2 min for NLB to provision):"
kubectl get svc hello-server
