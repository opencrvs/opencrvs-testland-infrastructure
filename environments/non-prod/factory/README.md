# Mastra Factory on non-prod

[Mastra Factory](https://factory.mastra.ai/) turns GitHub issues into plans and pull requests with coding agents. This folder deploys the self-hosted version to the non-prod cluster at https://factory.opencrvs.dev.

The deployment uses no Mastra platform services:

| Part        | What runs                                                   | File                  |
| ----------- | ----------------------------------------------------------- | --------------------- |
| Server      | `ghcr.io/opencrvs/factory`, built from `opencrvs/factory`   | `factory.yaml`        |
| Database    | Postgres 17 with pgvector                                   | `postgres.yaml`       |
| Network     | Policies that keep the agents away from other cluster pods  | `network-policy.yaml` |
| Sign-in     | WorkOS                                                      | Secret `factory-secrets` |
| GitHub      | A GitHub App that the OpenCRVS organization owns            | Secret `factory-github-app` |
| Sandboxes   | Local: the agents run commands inside the Factory pod       | `factory.yaml`        |

Both charts are the generic `opencrvs-addon` chart from `opencrvs-core/charts/opencrvs-addon`. Both pods stay on the node with the label `role: data2`, because their data is in hostPath folders on that node: `/data/factory` and `/data/factory-postgres`.

## Security

The agents run in the same container as the server, as the same user. An agent can read the server's environment, which includes the database password and the GitHub App private key. So:

- Install the GitHub App only on the repositories that Factory must change.
- Let Factory take only issues that maintainers label (for example `AI Friendly`). Do not let it take issues from outside authors without a check.
- `network-policy.yaml` blocks connections from the pod to private addresses, so the agents cannot reach the QA environments or the Kubernetes API. The pod can connect to the public internet.

## Set up

Do these steps one time. Keep the values that you generate in the team password manager.

### 1. DNS

Add an `A` record for `factory.opencrvs.dev`. Point it to the same public address as `metabase.opencrvs.org`. Traefik gets the TLS certificate from Let's Encrypt when the first request comes in.

### 2. WorkOS

1. In the [WorkOS dashboard](https://dashboard.workos.com), use the production environment.
2. Add `https://factory.opencrvs.dev/auth/callback` as a redirect URI.
3. Make an organization for OpenCRVS, and add the people who use Factory. Factory keeps its data per organization.
4. Copy the API key and the client ID.

### 3. GitHub App

In the `opencrvs` organization settings, open **Developer settings → GitHub Apps → New GitHub App**:

| Setting                 | Value                                                  |
| ----------------------- | ------------------------------------------------------ |
| Homepage URL            | `https://factory.opencrvs.dev`                         |
| Callback URL            | `https://factory.opencrvs.dev/auth/github/callback`    |
| Setup URL               | `https://factory.opencrvs.dev/auth/github/callback`    |
| Webhook URL             | `https://factory.opencrvs.dev/web/github/webhook`      |
| Webhook secret          | Output of `openssl rand -hex 32`                       |
| Repository permissions  | Contents: read and write. Issues: read and write. Pull requests: read and write. Metadata: read-only. |
| Events                  | Issues, Issue comment, Pull request, Pull request review, Pull request review comment |
| Where it can be installed | Only on this account                                 |

Then generate a client secret and a private key. Install the App on `opencrvs/opencrvs-core` only.

Pull requests from the App have a bot as author. Some opencrvs-core workflows skip bot pull requests: the feature environment deploy with E2E (`deploy-to-feature-environment.yml`) and the Claude review (`claude-review.yml`).

### 4. Namespace and secrets

```bash
kubectl create namespace factory
```

The database password goes into two secrets, so make it one time:

```bash
DB_PASSWORD=$(openssl rand -hex 24)

kubectl create secret generic factory-db-credentials \
  --namespace factory \
  --from-literal=POSTGRES_USER=factory \
  --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD"

kubectl create secret generic factory-secrets \
  --namespace factory \
  --from-literal=DATABASE_URL="postgres://factory:${DB_PASSWORD}@postgres.factory.svc.cluster.local:5432/factory" \
  --from-literal=FACTORY_CREDENTIAL_ENCRYPTION_KEY="$(openssl rand -base64 32)" \
  --from-literal=WORKOS_API_KEY=REPLACE_ME \
  --from-literal=WORKOS_CLIENT_ID=REPLACE_ME \
  --from-literal=WORKOS_COOKIE_PASSWORD="$(openssl rand -hex 32)"
```

Keep a backup of `FACTORY_CREDENTIAL_ENCRYPTION_KEY`. Factory uses it to encrypt the model keys and integration secrets in the database. Without the same key, Factory cannot read them.

Factory changes `\n` in `GITHUB_APP_PRIVATE_KEY` to new lines, so the next command puts the key on one line:

```bash
kubectl create secret generic factory-github-app \
  --namespace factory \
  --from-literal=GITHUB_APP_ID=REPLACE_ME \
  --from-literal=GITHUB_APP_PRIVATE_KEY="$(awk '{printf "%s\\n", $0}' path/to/private-key.pem)" \
  --from-literal=GITHUB_APP_CLIENT_ID=REPLACE_ME \
  --from-literal=GITHUB_APP_CLIENT_SECRET=REPLACE_ME \
  --from-literal=GITHUB_APP_SLUG=REPLACE_ME \
  --from-literal=GITHUB_APP_WEBHOOK_SECRET=REPLACE_ME
```

### 5. Install

Run these commands from this folder:

```bash
kubectl apply -n factory -f network-policy.yaml

helm upgrade --install postgres oci://ghcr.io/opencrvs/opencrvs-addon \
  --version v2.2.0 -n factory -f postgres.yaml

helm upgrade --install factory oci://ghcr.io/opencrvs/opencrvs-addon \
  --version v2.2.0 -n factory -f factory.yaml
```

Factory creates its tables when it starts. Check the start with:

```bash
kubectl -n factory logs deployment/factory -f
```

### 6. First sign-in

1. Open https://factory.opencrvs.dev and sign in with WorkOS.
2. In the onboarding wizard, select `opencrvs/opencrvs-core` and connect a model provider.
3. Open **Settings → Work Intake → GitHub issues**, turn on **Sync GitHub issues** and select the repository.
4. Change the intake rules so that only issues with the `AI Friendly` label get a card.

## Load and disk

The agents share the node with other workloads, so `factory.yaml` limits them:

- `MASTRACODE_DISPATCH_MAX_IN_FLIGHT` (2) and `MASTRACODE_DISPATCH_MAX_INTERACTIVE_IN_FLIGHT` (1) limit the agent runs that Factory starts at the same time. Some runs continue outside these slots, so the limit is not exact.
- Each session keeps a checkout of the repository in `/data/factory/home/.mastracode/web/sandboxes`, and Factory does not delete it. When the server starts, it deletes each session folder that had no change for `FACTORY_SESSION_MAX_IDLE_DAYS` (7) days. Changes that an agent did not push are lost with the folder.

The cleanup runs only at start. To free disk space, restart the deployment.

## Update

A push to `main` in `opencrvs/factory` publishes a new `latest` image. To use it, restart the deployment:

```bash
kubectl -n factory rollout restart deployment/factory
```

A restart stops the agent sessions that run at that time.

## Backups

No backup job covers `/data/factory-postgres`. The database has the cards, sessions, rules and encrypted credentials. To make a backup by hand:

```bash
kubectl -n factory exec deployment/postgres -- pg_dump -U factory factory > factory-$(date +%F).sql
```
