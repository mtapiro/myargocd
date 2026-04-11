# myArgoCD
K8s and ArgoCd Infrastructure

### 1. Install K8s cluster:
```bash

    #From  /k8s/create_cluster/ Run:
    terraform apply

```

### 2. Install and run ArgoCD
```bash

    # Install all we need for ArgoCD:
    # Install ArgoCD
    # Wait for ArgoCD to be ready
    # Auto-detect cluster info (cluster name, account ID, region, VPC ID)
    # Create IAM OIDC provider (if not exists)
    # Create IAM policy for Load Balancer Controller (if not exists)
    # Create IAM role & service account with proper permissions
    # Update the ArgoCD application with detected values
    # Apply all ArgoCD apps (which deploys everything via GitOps)
    ./scripts/bootstrap.sh  

    

    AWS_REGION=eu-west-1 ./scripts/setup-aws-lb-controller.sh      # Auto-detects & configures AWS LB Controller


```