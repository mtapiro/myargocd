#!/bin/bash
set -euo pipefail

# ArgoCD Setup Script
# Usage: ./scripts/argocd-setup.sh [install|apps|password|port-forward|all]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARGOCD_NAMESPACE="argocd"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

install_argocd() {
    log_info "Installing ArgoCD..."
    
    # Apply ArgoCD manifests
    kubectl apply -k "${PROJECT_ROOT}/k8s/argocd/overlays/default"
    
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${ARGOCD_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n ${ARGOCD_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n ${ARGOCD_NAMESPACE}
    
    log_success "ArgoCD installed successfully"
}

get_password() {
    log_info "Getting ArgoCD admin password..."
    
    if kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NAMESPACE} &> /dev/null; then
        PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        echo ""
        log_success "ArgoCD Admin Credentials:"
        echo -e "  Username: ${GREEN}admin${NC}"
        echo -e "  Password: ${GREEN}${PASSWORD}${NC}"
        echo ""
    else
        log_warn "Initial admin secret not found. Password may have been changed."
    fi
}

deploy_apps() {
    log_info "Deploying ArgoCD Applications..."
    
    # Check if ArgoCD is running
    if ! kubectl get deployment argocd-server -n ${ARGOCD_NAMESPACE} &> /dev/null; then
        log_error "ArgoCD is not installed. Run './scripts/argocd-setup.sh install' first."
        exit 1
    fi
    
    # Apply ArgoCD apps
    kubectl apply -k "${PROJECT_ROOT}/k8s/argocd-apps/"
    
    log_success "ArgoCD Applications deployed"
    log_info "Checking applications..."
    sleep 5
    kubectl get applications -n ${ARGOCD_NAMESPACE}
}

port_forward() {
    log_info "Starting port-forward to ArgoCD server..."
    echo ""
    echo -e "Access ArgoCD UI at: ${GREEN}http://localhost:8080${NC}"
    echo "Press Ctrl+C to stop port-forwarding"
    echo ""
    
    # Use HTTP port 80 (server.insecure=true means HTTP mode)
    kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:80
}

show_status() {
    log_info "ArgoCD Status:"
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n ${ARGOCD_NAMESPACE}
    echo ""
    echo "=== Applications ==="
    kubectl get applications -n ${ARGOCD_NAMESPACE} 2>/dev/null || echo "No applications found"
    echo ""
    echo "=== ApplicationSets ==="
    kubectl get applicationsets -n ${ARGOCD_NAMESPACE} 2>/dev/null || echo "No applicationsets found"
}

usage() {
    echo "ArgoCD Setup Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install       Install ArgoCD to the cluster"
    echo "  apps          Deploy ArgoCD Applications"
    echo "  password      Get ArgoCD admin password"
    echo "  port-forward  Start port-forward to ArgoCD UI"
    echo "  status        Show ArgoCD status"
    echo "  all           Run install, apps, and show password"
    echo ""
}

# Main
case "${1:-}" in
    install)
        check_prerequisites
        install_argocd
        ;;
    apps)
        check_prerequisites
        deploy_apps
        ;;
    password)
        check_prerequisites
        get_password
        ;;
    port-forward)
        check_prerequisites
        port_forward
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    all)
        check_prerequisites
        install_argocd
        get_password
        deploy_apps
        ;;
    *)
        usage
        exit 1
        ;;
esac
