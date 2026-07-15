# Manual Deployment on existing kubernetes cluster

> NOTE: If you would like to provision infrastructure and kubernetes cluster with ansible scripts developed by OpenCRVS Team, please use [Deploy with Github](#deploy-with-github) scenario. Manual deployment scenario covers only OpenCRVS and dependencies installation.

## Prerequisites

Single-node Kubernetes cluster is up and running on your VM.
Make sure you are able connect to the cluster with kubectl

```
kubectl get nodes
```

## Installation process

> ℹ️ All commands should be started from `examples/dev` directory

1. Deploy traefik
   ```
   helm upgrade --install traefik oci://ghcr.io/traefik/helm/traefik \
      --namespace traefik \
      --create-namespace \
      -f traefik/values.yaml
   ```
2. Install OpenCRVS dependencies
   > ⚠️ Update `<your_host_name>` placeholder before running command
   ```
   helm upgrade --install opencrvs-deps oci://ghcr.io/opencrvs/opencrvs-dependencies-chart \
   --namespace "opencrvs-deps-dev" \
   -f examples/dev/dependencies/values.yaml \
   --create-namespace \
   --set storage_type=host_path \
   --set hostname=<your_host_name>
   ```
3. Install OpenCRVS MOSIP integration
   > ⚠️ Update `<your_host_name>` placeholder before running command
   ```
   helm upgrade --install mosip-api oci://ghcr.io/opencrvs/opencrvs-mosip \
       --namespace "opencrvs-dev" \
       -f mosip-api/values.yaml \
       --create-namespace \
       --atomic \
       --set hostname=<your_host_name>
   ```
4. Copy secrets from dependencies to main namespace:
   ```
   secrets=(
        "elasticsearch-admin-user"
        "redis-opencrvs-users"
        "minio-opencrvs-users"
        "postgres-admin-user"
    )
    for secret in "${secrets[@]}"; do
        kubectl get secret $secret -n opencrvs-deps-dev -o yaml \
        | sed "s#namespace: opencrvs-deps-dev#namespace: opencrvs-dev#" \
        | grep -vE 'resourceVersion|uid|creationTimestamp' \
        | kubectl apply -n opencrvs-dev -f -
    done
   ```
5. Install OpenCRVS
   > ⚠️ Update `<your_host_name>` placeholder before running command
   ```
   helm upgrade --install opencrvs oci://ghcr.io/opencrvs/opencrvs-services \
       --timeout 15m \
       --namespace "opencrvs-dev" \
       -f opencrvs-services/values.yaml \
       --create-namespace \
       --atomic \
       --set hostname=<your_host_name>
   ```
6. Seed data
   ```
   helm get values opencrvs --namespace "opencrvs-dev" \
      | helm template -f - \
           --set data_seed.enabled=true \
           --namespace "opencrvs-dev" \
           -s templates/data-seed-job.yaml \
           oci://ghcr.io/opencrvs/opencrvs-services \
      | kubectl apply --namespace "opencrvs-dev" -f -
   ```
