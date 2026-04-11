#!/bin/bash
set -e

echo "=========================================="
echo "ArgoCD GitOps Bootstrap Script"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"

# Step 1: Create ArgoCD namespace
echo -e "\n${YELLOW}Step 1: Creating argocd namespace...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Install ArgoCD (using server-side apply to handle large CRDs)
echo -e "\n${YELLOW}Step 2: Installing ArgoCD...${NC}"
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Step 3: Wait for ArgoCD to be ready
echo -e "\n${YELLOW}Step 3: Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n argocd

echo -e "${GREEN}ArgoCD is ready${NC}"

# Step 4: Setup AWS Load Balancer Controller (IAM roles and policy)
echo -e "\n${YELLOW}Step 4: Setting up AWS Load Balancer Controller...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/setup-aws-lb-controller.sh"

# Step 5: Apply ArgoCD configuration patches
echo -e "\n${YELLOW}Step 5: Applying ArgoCD configuration...${NC}"
kubectl apply --server-side --force-conflicts -k k8s/argocd/overlays/default/

# Step 6: Apply ArgoCD Apps (this will bootstrap everything else via GitOps)
echo -e "\n${YELLOW}Step 6: Applying ArgoCD Apps (GitOps bootstrap)...${NC}"
kubectl apply --server-side --force-conflicts -k k8s/argocd-apps/

echo -e "\n${GREEN}=========================================="
echo "Bootstrap complete!"
echo "==========================================${NC}"

# Get initial admin password
echo -e "\n${YELLOW}ArgoCD Admin Password:${NC}"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

echo -e "\n${YELLOW}To access ArgoCD UI (port-forward):${NC}"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then open: https://localhost:8080"

echo -e "\n${YELLOW}Once DNS is configured, access via:${NC}"
echo "https://argo.tapiromeir.com"

echo -e "\n${YELLOW}ArgoCD will now automatically deploy:${NC}"
echo "  - aws-load-balancer-controller"
echo "  - cert-manager"
echo "  - nginx-ingress"
echo "  - cluster-issuer (Let's Encrypt)"
echo "  - workloads (testsite-dev, etc.)"

echo -e "\n${GREEN}Monitor progress in ArgoCD UI or with:${NC}"
echo "kubectl get applications -n argocd -w"
