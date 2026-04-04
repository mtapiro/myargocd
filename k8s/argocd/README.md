# ArgoCD Installation

This directory contains the ArgoCD installation manifests using Kustomize.

## Directory Structure

```
argocd/
├── base/
│   ├── kustomization.yaml    # Pulls ArgoCD from upstream
│   └── namespace.yaml        # ArgoCD namespace
└── overlays/
    └── default/
        ├── kustomization.yaml           # Main overlay
        ├── argocd-cm-patch.yaml         # ArgoCD ConfigMap customizations
        └── argocd-cmd-params-cm-patch.yaml  # Server/controller parameters
```

## Installation

### 1. Install ArgoCD

```bash
# Preview the manifests
kubectl kustomize k8s/argocd/overlays/default

# Install ArgoCD
kubectl apply -k k8s/argocd/overlays/default

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 2. Get Initial Admin Password

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### 3. Access ArgoCD UI

```bash
# Port forward (for local access)
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Access at: http://localhost:8080
# Username: admin
# Password: (from step 2)
```

### 4. Install ArgoCD CLI (Optional)

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Login
argocd login localhost:8080 --insecure
```

## Configuration

### Updating ArgoCD Version

Edit `base/kustomization.yaml` and update the version in the URL:

```yaml
resources:
  - namespace.yaml
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.3/manifests/install.yaml
```

### Adding Custom Configuration

1. **ConfigMap patches**: Add to `overlays/default/argocd-cm-patch.yaml`
2. **Server parameters**: Add to `overlays/default/argocd-cmd-params-cm-patch.yaml`
3. **Resource patches**: Create new patch files and reference in kustomization.yaml

### Common Customizations

#### Enable SSO (Example: GitHub)

Add to `argocd-cm-patch.yaml`:

```yaml
data:
  url: https://argocd.example.com
  dex.config: |
    connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: $dex.github.clientID
          clientSecret: $dex.github.clientSecret
          orgs:
            - name: your-org
```

#### Configure RBAC

Create `argocd-rbac-cm-patch.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    g, your-org:devops, role:admin
    g, your-org:developers, role:readonly
  policy.default: role:readonly
```

## Exposing ArgoCD

### Option 1: AWS ALB Ingress

See `ingress-alb.yaml` example in this directory.

### Option 2: Nginx Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
```

## Troubleshooting

### Check ArgoCD pods

```bash
kubectl get pods -n argocd
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-repo-server
kubectl logs -n argocd deployment/argocd-application-controller
```

### Reset admin password

```bash
# Generate new bcrypt hash
argocd account bcrypt --password <new-password>

# Update the secret
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "<bcrypt-hash>", "admin.passwordMtime": "'$(date +%FT%T%Z)'"}}'
```

### Clear application cache

```bash
kubectl delete secret -n argocd -l argocd.argoproj.io/secret-type=repo-creds
```
