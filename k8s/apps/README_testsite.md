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


### Port forward (k9s) :
```bash
# 1. Go to ns (dev, stage or prod) --> Pod (testsite-68c4bb986f-2pl9t)
# 2. Shift+F --> ok
# in the browser: http://localhost:8080 (or any port you choose)

```