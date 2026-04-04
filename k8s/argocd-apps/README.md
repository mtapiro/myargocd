# ArgoCD Applications

This directory contains ArgoCD Application and ApplicationSet definitions for managing workloads using GitOps.

## Directory Structure

```
argocd-apps/
├── kustomization.yaml           # Main kustomization file
├── base/
│   └── root-app.yaml           # Root application (App of Apps)
├── projects/
│   └── workloads-project.yaml  # AppProject for workloads
└── applicationsets/
    └── workloads-appset.yaml   # ApplicationSet for auto-discovery
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        ArgoCD Server                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐                                           │
│  │   Root App      │ ─── Manages ───▶ argocd-apps/             │
│  │  (App of Apps)  │                                           │
│  └────────┬────────┘                                           │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐      ┌─────────────────────────────────┐ │
│  │  AppProject:    │      │  ApplicationSet: workloads      │ │
│  │  workloads      │◀─────│  (Matrix: envs × apps)          │ │
│  │  - RBAC         │      └──────────────┬──────────────────┘ │
│  │  - Destinations │                     │                     │
│  └─────────────────┘                     │                     │
│                                          │ Generates           │
│           ┌──────────────────────────────┼──────────────────┐ │
│           ▼                              ▼                  ▼  │
│  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐│
│  │ testsite-dev   │    │ testsite-stage │    │ testsite-prod  ││
│  │ (auto-sync)    │    │ (auto-sync)    │    │ (manual-sync)  ││
│  └────────┬───────┘    └────────┬───────┘    └────────┬───────┘│
│           │                     │                      │        │
└───────────┼─────────────────────┼──────────────────────┼────────┘
            ▼                     ▼                      ▼
    ┌───────────────┐    ┌───────────────┐    ┌───────────────┐
    │  Namespace:   │    │  Namespace:   │    │  Namespace:   │
    │     dev       │    │     stage     │    │     prod      │
    └───────────────┘    └───────────────┘    └───────────────┘
```

## Setup

### Prerequisites

1. ArgoCD installed (see `../argocd/README.md`)
2. Git repository URL configured

### Step 1: Update Repository URL

Before deploying, update the repository URL in:

1. `applicationsets/workloads-appset.yaml` (2 places)
2. `base/root-app.yaml` (1 place)

Replace `https://github.com/your-org/myargocd.git` with your actual repository URL.

### Step 2: Deploy Applications

```bash
# Option A: Apply directly (recommended for initial setup)
kubectl apply -k k8s/argocd-apps/

# Option B: Use ArgoCD CLI
argocd app create root-app \
  --repo https://github.com/your-org/myargocd.git \
  --path k8s/argocd-apps \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd \
  --sync-policy automated
```

### Step 3: Verify Applications

```bash
# Check ApplicationSet
kubectl get applicationset -n argocd

# Check generated Applications
kubectl get applications -n argocd

# Using ArgoCD CLI
argocd app list
```

## ApplicationSet Configuration

The `workloads-appset.yaml` uses a **Matrix Generator** that combines:

1. **Environments** (dev, stage, prod)
2. **Applications** (auto-discovered from `k8s/apps/base/`)

### Environment Settings

| Environment | Auto-Sync | Prune | Self-Heal | Sync Wave |
|-------------|-----------|-------|-----------|-----------|
| dev         | ✅        | ✅    | ✅        | 1         |
| stage       | ✅        | ✅    | ✅        | 2         |
| prod        | ❌        | ❌    | ❌        | 3         |

### Adding a New Application

1. Create the app in `k8s/apps/base/<app-name>/`
2. Add it to environment overlays
3. The ApplicationSet automatically discovers and creates ArgoCD Applications

### Adding a New Environment

Add to the `list` generator in `workloads-appset.yaml`:

```yaml
- env: qa
  namespace: qa
  syncWave: "1.5"
  autoSync: true
  prune: true
```

## AppProject (workloads)

The `workloads` project provides:

- **Source restrictions**: Configure allowed repositories
- **Destination restrictions**: Only dev/stage/prod namespaces
- **RBAC roles**: developer (read-only), devops (full access)
- **Sync windows**: (Optional) Prevent prod deployments during business hours

### RBAC Configuration

```yaml
roles:
  - name: developer
    policies:
      - p, proj:workloads:developer, applications, get, workloads/*, allow
      - p, proj:workloads:developer, applications, sync, workloads/*-dev, allow

  - name: devops
    policies:
      - p, proj:workloads:devops, applications, *, workloads/*, allow
```

## Operations

### Sync an Application

```bash
# Using CLI
argocd app sync testsite-dev

# Force sync with prune
argocd app sync testsite-dev --prune

# Sync all apps in project
argocd app sync -l app.kubernetes.io/part-of=workloads
```

### Rollback

```bash
# List revisions
argocd app history testsite-prod

# Rollback to specific revision
argocd app rollback testsite-prod <revision>
```

### Manual Production Deployment

Since prod has auto-sync disabled:

```bash
# Review changes first
argocd app diff testsite-prod

# Sync when ready
argocd app sync testsite-prod
```

## Troubleshooting

### Application stuck in "Progressing"

```bash
kubectl describe application <app-name> -n argocd
argocd app get <app-name> --show-params
```

### Sync failed

```bash
argocd app get <app-name> --show-operation
kubectl logs -n argocd deployment/argocd-application-controller
```

### ApplicationSet not generating apps

```bash
kubectl describe applicationset workloads -n argocd
kubectl logs -n argocd deployment/argocd-applicationset-controller
```
