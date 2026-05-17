###############################################################
# argocd/install.sh
# Installs ArgoCD, AWS Load Balancer Controller, and ArgoCD apps
# Run AFTER `terraform apply` and with kubectl configured for EKS
#
# Usage: ./install.sh [CLUSTER_NAME] [AWS_REGION]
# Example: ./install.sh AppS-dev-eks eu-central-1
###############################################################

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

CLUSTER_NAME="${1:-AppS-dev-eks}"
REGION="${2:-eu-central-1}"
ARGOCD_VERSION="v2.10.0"
ALB_CHART_VERSION="1.7.2"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' is required but not found in PATH." >&2
    exit 1
  fi
}

require_cmd aws
require_cmd kubectl
require_cmd helm
require_cmd terraform

if grep -q '<YOUR-ORG>' "$SCRIPT_DIR/nginx-application.yaml" 2>/dev/null; then
  echo "WARNING: Replace <YOUR-ORG>/<YOUR-REPO> in argocd/project.yaml and argocd/nginx-application.yaml"
  echo "         before ArgoCD can sync manifests from Git."
  echo ""
fi

echo "==> Updating kubeconfig for cluster: $CLUSTER_NAME"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "==> Creating argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD $ARGOCD_VERSION"
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"

echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "==> Patching argocd-server service to LoadBalancer"
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "==> Installing AWS Load Balancer Controller via Helm"
helm repo add eks https://aws.github.io/eks-charts
helm repo update

ALB_ROLE_ARN="$(terraform -chdir="$TERRAFORM_DIR" output -raw alb_controller_role_arn)"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "$ALB_CHART_VERSION" \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ALB_ROLE_ARN" \
  --wait \
  --timeout 5m

echo "==> Waiting for ALB controller..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s

echo "==> Applying ArgoCD AppProject and Application"
kubectl apply -f "$SCRIPT_DIR/project.yaml"
kubectl apply -f "$SCRIPT_DIR/nginx-application.yaml"

echo ""
echo "==> ArgoCD LoadBalancer hostname (may take 2-3 min to provision):"
kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || true
echo ""

echo "==> Retrieve initial ArgoCD admin password:"
echo "    kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "      -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "==> Or use port-forward instead of LoadBalancer:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "    Then open: https://localhost:8080  (user: admin)"
echo ""
echo "==> Watch NGINX app sync:"
echo "    kubectl get application nginx -n argocd -w"
