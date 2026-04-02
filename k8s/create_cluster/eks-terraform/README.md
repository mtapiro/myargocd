#To Generate KUBECONFIG after terraform apply:
- terraform output -raw kubeconfig > kubeconfig.yaml
- export KUBECONFIG=$PWD/kubeconfig.yaml
- OR: 
    - kubectl get nodes
    - k9s