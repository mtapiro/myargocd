# Kubernetes Applications - Kustomize Structure

This directory contains Kubernetes manifests organized using Kustomize for multi-environment deployments.

## Directory Structure

```
apps/
├── base/                    # Base configurations (shared across environments)
│   └── <app-name>/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── kustomization.yaml
├── overlays/                # Environment-specific configurations
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   ├── stage/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   └── prod/
│       ├── kustomization.yaml
│       └── patches/
└── README.md
```

## Usage

### Preview manifests for an environment

```bash
# Preview dev environment
kubectl kustomize k8s/apps/overlays/dev

# Preview stage environment
kubectl kustomize k8s/apps/overlays/stage

# Preview prod environment
kubectl kustomize k8s/apps/overlays/prod
```

### Deploy to an environment

```bash
# Deploy to dev
kubectl apply -k k8s/apps/overlays/dev

# Deploy to stage
kubectl apply -k k8s/apps/overlays/stage

# Deploy to prod
kubectl apply -k k8s/apps/overlays/prod
```

### Delete a Deploy:
```bash
# Delete dev
kubectl delete -k k8s/apps/overlays/dev

```

## Adding a New Application

1. Create a new directory under `base/` with your app name:
   ```bash
   mkdir -p k8s/apps/base/<new-app-name>
   ```

2. Add your base manifests:
   - `deployment.yaml`
   - `service.yaml` (if needed)
   - `kustomization.yaml`

3. Add the new app to each environment's `kustomization.yaml`:
   ```yaml
   resources:
     - ../../base/testsite
     - ../../base/<new-app-name>  # Add this line
   ```

4. Create environment-specific patches if needed:
   ```bash
   touch k8s/apps/overlays/dev/patches/<new-app-name>-deployment.yaml
   ```

## ECR Authentication

For pulling images from AWS ECR, you need to create an image pull secret.

### Option 1: Using AWS ECR Credential Helper (Recommended)

Configure the ECR credential helper on your nodes or use IRSA (IAM Roles for Service Accounts).

### Option 2: Create Secret Manually

```bash
# Get ECR token
aws ecr get-login-password --region eu-west-1 | \
  kubectl create secret docker-registry ecr-registry-secret \
    --docker-server=609177096835.dkr.ecr.eu-west-1.amazonaws.com \
    --docker-username=AWS \
    --docker-password-stdin \
    -n <namespace>
```

Note: ECR tokens expire after 12 hours. Consider using a CronJob or external-secrets for automatic rotation.

## Environment Differences

| Environment | Replicas | CPU Requests | CPU Limits | Memory Requests | Memory Limits |
|-------------|----------|--------------|------------|-----------------|---------------|
| dev         | 1        | 100m         | 200m       | 100Mi           | 128Mi         |
| stage       | 2        | 150m         | 250m       | 128Mi           | 150Mi         |
| prod        | 3        | 200m         | 300m       | 128Mi           | 150Mi         |

## ArgoCD Integration

Each overlay can be used as an ArgoCD Application source:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: testsite-dev
  namespace: argocd
spec:
  source:
    repoURL: <your-repo-url>
    path: k8s/apps/overlays/dev
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
