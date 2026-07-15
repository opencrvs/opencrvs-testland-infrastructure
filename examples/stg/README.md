# General information

# TODO: UPDATE REQUIRED, please check examples/dev

This example shows how to deploy OpenCRVS with Farajaland data on multi-node kubernetes cluster. OpenCRVS can be deployed manually or using GitHub Action Workflows.

# Information about deployment package

Following components are included into deployment:

- Traefik v3.4.3, official helm chart is used (traefik-36.3.0)
- Datastores, see OpenCRVS dependencies helm chart for exact versions:
  - Postgres
  - Elasticsearch
  - Redis
  - MinIO
- Monitoring and Logging, see OpenCRVS dependencies helm chart for exact versions:
  - Kibana
  - Logstash
  - Filebeat
  - Metricbeat
  - Elastic APM server
  - Elastalert2
- OpenCRVS services are deployed with Farajaland data and MOSIP integration enabled:
  - Core packages version: 0f10027
  - Farajaland version: 3314a9a
- MOSIP package

# Prerequisites

1. 3 VMs has at least:

- Master 2cpu/4G RAM/10G ssd
- Workers 8cpu/16G RAM/50G ssd

2. Linux distribution Ubuntu 24.04 is installed on VM
3. At least master VM has public IP, or at least you have option to open ports 80 and 443, otherwise traefik will not be able to issue valid SSL Certificates with lets encrypt http-01 challenge.
4. Valid Domain name is attached to VM. You need to have 2 `A` records:
   - Primary domain for master VMs IP address (e/g: opencrvs.example.com)
   - Wildcard for primary domain or list of sub-domains mapped to master VMs IP address.

   For more information, please check https://documentation.opencrvs.org/setup/3.-installation/3.3-set-up-a-server-hosted-environment/3.3.5-setup-dns-a-records#domain-a-records

5. Provision user is configured according to documentation at [3.3.1-provision-your-server-nodes-with-ssh-access](https://documentation.opencrvs.org/setup/3.-installation/3.3-set-up-a-server-hosted-environment/3.3.1-provision-your-server-nodes-with-ssh-access)
6. Make sure new ssh key-pair is generated on master:

- On master node run `ssh-keygen`, feel free to use defaults
- On master node keep private and public keys in /home/provision/.ssh
- On worker node keep only public key in /home/provision/.ssh/authorized_keys
- Make sure command `ssh <worker node ip>` works without asking for password

# Deploy OpenCRVS with Github Actions workflows

## Prerequisites

> NOTE: `(Optional)` steps should be performed only once per multiple environments

1. (Optional) Fork repository: https://github.com/opencrvs/infrastructure
2. (Optional) Create repository level secrets:
   - GH_TOKEN with read/write access to workflows
   - K8S_RUNNER_TOKEN, Kubernetes self-hosted runner secret
3. Create GitHub environment `demo`
4. Create following GitHub secrets under `demo` environment:
   - ENCRYPTION_KEY, `/data` partition encryption key, store secret to password manager for future usage
5. Create following GitHub variables under `demo` environment:
   - DISK_SPACE, encrypted partition disk size, for testing 5g is more then sufficient
   - DOMAIN, domain name attached to your VM

## Bootstrap github self-hosted runner

Make sure you have following values:

- github org name: `<your account or org name>`
- github repository name: `<your repository name>`
- github PAT with access to repository code and workflow: `<K8S_RUNNER_TOKEN or dedicated runner token>`
- environment name: `demo`

Run following command on VM (master node):

```
curl -sS https://raw.githubusercontent.com/opencrvs/infrastructure/develop/scripts/bootstrap/node-runner.sh -o /tmp/node-runner.sh && bash /tmp/node-runner.sh
```

You should see a message:

```
✅ Runner '....-runner' is installed and started!
```

In your github repository you should see a self-hosted runner under settings/actions/runners

## Prepare inventory file

1. Go to `infrastructure/server-setup/inventory` folder
2. Create configuration file for your dev VM, name should match with GitHub environment name, e/g if your environment name is `demo` then file name should be `demo.yml`. See example.
3. Commit your changes
4. Make sure update-envs workflow completed before moving to the next section.

Configuration file example:

```yaml
all:
  vars:
    kube_api_sans:
      - test-k8s.opencrvs.dev
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
    ansible_user: provision
    users:
      - name: demo
        ssh_keys:
          - ssh-ed25519 AAAAC3NzaC....i2DqV7g/Q
        state: present
        role: admin
  children:
    master:
      hosts:
        test-k8s-master:
          ansible_host: 10.2.1.1

    workers:
      hosts:
        test-k8s-worker-0:
          ansible_host: 10.2.1.2
        test-k8s-worker-1:
          ansible_host: 10.2.1.3
```

## Run provision

- Run provision workflow
- Make sure kubernetes self-hosted runner is available at settings/actions/runners

## Run Dependencies deployment workflow

Review file `examples/demo/dependencies/values.yaml` and if needed adjust values, defaults should be good for starting point

- Label kubernetes nodes:
  ```
  kubectl label node test-k8s-worker-0 role=data1
  kubectl label node test-k8s-worker-1 role=data2
  ```
- Run Dependencies deployment workflow
- Make sure minio and kibana are available

## Run OpenCRVS deployment workflow

Review file `examples/demo/opencrvs-services/values.yaml` and if needed adjust values, defaults should be good for starting point

- Run OpenCRVS deployment workflow
- Make sure login page is available

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
   helm upgrade --install traefik traefik-repo/traefik \
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
   ENV=demo
   secrets=(
        "elasticsearch-admin-user"
        "redis-opencrvs-users"
        "minio-opencrvs-users"
        "postgres-admin-user"
    )
    for secret in "${secrets[@]}"; do
        kubectl get secret $secret -n opencrvs-deps-${ENV} -o yaml \
        | sed "s#namespace: opencrvs-deps-${ENV}#namespace: opencrvs-${ENV}#" \
        | grep -vE 'resourceVersion|uid|creationTimestamp' \
        | kubectl apply -n opencrvs-${ENV} -f -
    done
   ```
5. Install OpenCRVS
   > ⚠️ Update `<your_host_name>` placeholder before running command
   ```
   helm upgrade --install opencrvs oci://ghcr.io/opencrvs/opencrvs-services \
       --timeout 15m \
       --namespace "opencrvs-demo" \
       -f opencrvs-services/values.yaml \
       --create-namespace \
       --atomic \
       --set hostname=<your_host_name>
   ```
6. Seed data
   ```
   helm get values opencrvs --namespace "opencrvs-demo" \
      | helm template -f - \
           --set data_seed.enabled=true \
           --namespace "opencrvs-demo" \
           -s templates/data-seed-job.yaml \
           oci://ghcr.io/opencrvs/opencrvs-services \
      | kubectl apply --namespace "opencrvs-demo" -f -
   ```
