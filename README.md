# myArgoCD
K8s and ArgoCd Infrastructure

### Install and run ArgoCD
```bash

# Install ArgoCD
./scripts/argocd-setup.sh install

# Get admin password
./scripts/argocd-setup.sh password

# Deploy ArgoCD applications
./scripts/argocd-setup.sh apps

# Access UI (port-forward)
./scripts/argocd-setup.sh port-forward
# Then open https://localhost:8080

```