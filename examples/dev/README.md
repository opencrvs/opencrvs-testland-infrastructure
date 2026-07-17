# General Information

This guide describes how to deploy **OpenCRVS** with **Farajaland** sample data on a single-node Kubernetes cluster running on a virtual machine.

OpenCRVS can be deployed either:

- **Manually** (using Helm and CLI commands), see [README-on-existing-cluster](README-on-existing-cluster.md) or
- **Automatically** (using the provided GitHub Action Workflows).

---

# Deployment Package Contents

The deployment package includes the following components:

- **Ingress**

  - [Traefik](https://doc.traefik.io/traefik/)

- **Datastores** (via the [OpenCRVS dependencies Helm chart](../../charts/dependencies/)):

  - PostgreSQL
  - Elasticsearch
  - Redis
  - MinIO

- **Monitoring and Logging** (via the dependencies Helm chart):

  - Kibana
  - Logstash
  - Filebeat
  - Metricbeat
  - Elastic APM Server
  - Elastalert2

- **OpenCRVS Services** deployed with **Farajaland data** and **MOSIP integration** enabled:
  - Core packages version: `v1.9.0-beta-1`
  - Farajaland version: `v1.9.0-beta-1`
  - MOSIP integration version: `latest`

---

# Prerequisites

## Hardware and software requirements

Before starting the deployment, ensure the following requirements are met:

**1. Virtual Machine resources**

- Minimum: **8 CPU cores, 16 GB RAM, 50 GB SSD**.

**2. Operating System**

- VM is running **Ubuntu 24.04 LTS**.

**3. Networking and Domain Configuration**

- The VM must have a **public IP address** and (or) ports **80** and **443** must be accessible.
- A **valid domain name** must be configured and point to the VM.
- Required DNS records:

  - An **A record** pointing the primary domain to the VM IP (e.g., `opencrvs.example.com`).
  - A **wildcard A record** (e.g., `*.opencrvs.example.com`) or individual subdomains pointing to the same VM IP.

- These settings are required for **Traefik** to issue valid SSL certificates using Let’s Encrypt (`http-01` challenge).

> See the [OpenCRVS documentation on DNS setup](https://documentation.opencrvs.org/setup/3.-installation/3.3-set-up-a-server-hosted-environment/3.3.5-setup-dns-a-records#domain-a-records) for details.
> If you don't have public IP Address please follow guide "How to run traefik with self-signed SSL Certificate", see [TODO](#link-goes-here)

## Country Config template custom docker image

OpenCRVS requires custom Country Config docker image for configuration.

- Fork country config repository https://github.com/opencrvs/opencrvs-countryconfig
- Create Docker Hub account or use your own private docker registry
- Push build and push image to the docker registry
- Create Docker Hub API access key or use your own way for authentication into private registry.

For more details check developers documentation [TODO](link)

---

# Deploy OpenCRVS with GitHub Actions Workflows

This section describes how to deploy OpenCRVS using the provided GitHub Action workflows. The workflows automate provisioning of the infrastructure, deployment of dependencies, and deployment of OpenCRVS services.

Fork [opencrvs/infrastructure](https://github.com/opencrvs/infrastructure) into your own GitHub account or organization.

You will need to provide the following values and answers to the following questions:

- GitHub organization or account name: `<your-org-or-account>`
- GitHub repository name: `<your-repository>`
- GitHub PAT (personal access token) with access to repository code and workflows: `<GH_TOKEN or dedicated token>`
- Choose environment type, depending on answer additional questions will be asked.
- Environment name: `<env name>`
- Provide ip addresses for worker nodes and backup server
- For production environment provide list of GutHub users allowed to approve production workflows.
- Configure Email/SMS notifications for alerting

> [!NOTE]
> OpenCRVS environment is provisioned with and deployed as Helm charts. Configuration files are created at first run of `yarn environment:init`, all further changes should be made manually at `environments/<environment name>/`

---

## 1. Create a GitHub environment

- Checkout forked infrastructure repository into any folder on your laptop
  ```
  git clone <repository url>
  ```
- Install yarn dependencies:
  ```
  yarn
  ```
- Create environment:
  ```
  yarn environment:init
  ```
- Answer all questions, pay attention to the following items
- On the final step you will get code snipped with command to be executed on servers (master, worker, backup), example:
  ```
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Follow the steps below to complete the setup of your environment:
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ➡️ Run following command on Kubernetes master VM to bootstrap self-hosted runner:

  curl -sfL https://raw.githubusercontent.com/opencrvs/infrastructure/refs/heads/develop/scripts/bootstrap/opencrvs-bootstrap.sh -o opencrvs-bootstrap.sh && \
  bash opencrvs-bootstrap.sh --owner foo \
            --repo bar \
            --env demo \
            --token ghp_token \
            --enable-runner


  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ```
- Save generated snippet for later usage
- Go to GitHub and verify the newly created environment
- Commit configuration files generated at `environments/<environment name>/` into git

## 2. Bootstrap GitHub Self-Hosted Runner

The self-hosted runner must be installed on the single VM (master node). The VM must be provisioned with an SSH user account according to [Provision Your Server Nodes with SSH Access](https://documentation.opencrvs.org/setup/3.-installation/3.3-set-up-a-server-hosted-environment/3.3.1-provision-your-server-nodes-with-ssh-access).

> NOTE: Use code snippet generated on previous step.

1. Login as user with sudo access or as root

2. Run the following command on the VM:
   ```bash
   curl -sfL https://raw.githubusercontent.com/opencrvs/infrastructure/refs/heads/ocrvs-9792/scripts/bootstrap/opencrvs-bootstrap.sh -o opencrvs-bootstrap.sh | \
   bash opencrvs-bootstrap.sh --owner <org name> \
               --repo <repo name> \
               --env <env name> \
               --token <github token> \
               --enable-runner
   ```

**Checklist for script execution**

1. Verify `provision` user was created:
   ```
   ls -l /home/provision
   su - provision
   ```
2. In your GitHub repository, navigate to **Settings → Actions → Runners** and verify that the runner appears as a self-hosted runner.

---

## 3. Run Infrastructure Provision

- Trigger the **provision workflow** from your repository.

Verification steps:

- Verify that the Kubernetes self-hosted runner is visible under **Settings → Actions → Runners**.
- You should be able to logic with any user defined under `users` section of inventory file.
- You should have access to kubernetes cluster after login, run command `kubectl config current-context`
- Copy `.kube/config` to your laptop and configure `kubectl` locally instead of remote connection

---

## 4. Run Dependencies Deployment

- Run the **Deploy dependencies**.
- Verify that **MinIO** and **Kibana** are available:
  - Kibana URL: `https://kibana.<your domain>`
  - MinIO URL: `https://minio.<your domain>`
  > NOTE: Credentials are stored at GitHub secrets or can be fetched namespace `opencrvs-deps-<env>`.

---

## 6. Run OpenCRVS Deployment

In this configuration OpenCRVS is deployed with MOSIP integration enabled and Farajaland base image.
Data seed script also executed at the end of deployment workflow.

- Run the **Deploy OpenCRVS** workflow with following properties:
  - Tag of the core image: v1.9.0-beta-1
  - Tag of the countryconfig image: v1.9.0-beta-1
  - Target environment: `<your env>` (dev)
  - Reset environment after deploy: ✅ (checked)
  - Deploy MOSIP integration: ✅ (checked)

4. Verify that the **OpenCRVS login page** is accessible via your configured domain.

---

✅ At this point, OpenCRVS should be successfully deployed on your single-node Kubernetes cluster.

Verification steps:

- Go to login page: `https://<your domain>`
- Login using demo users: https://documentation.opencrvs.org/setup/3.-installation/3.1-set-up-a-development-environment/3.1.4-log-in-to-opencrvs-locally

# Advanced topics

## Running traefik behind VPN

### DNS Challenge

Please check configuration file with example for Cloudflare at [here](./traefik/values-dns-challenge.yaml)

### Custom SSL Certificate

Please check configuration file with example for Custom SSL Certificate at [here](./traefik/values-custom-ssl.yaml)
