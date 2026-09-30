# DevOps Upgrade Checklist

**Audience:** maintainers of this infrastructure repository preparing a new
OpenCRVS release — not a runbook for sysadmins/operators/devops running an
already-provisioned environment.

For each minor OpenCRVS release, walk this table and confirm every dependency is
either intentionally left pinned or bumped. Update the table itself whenever a
dependency's tracking mechanism changes (new variable, moved to a different file, etc).

It also doubles as a troubleshooting reference: when a component behaves
unexpectedly, use the table to find where its version is pinned and how to check
what's actually running, to rule out a version mismatch as the cause.

## Tracked-by legend

| Tag | Meaning |
|---|---|
| `ansible` | Version is a variable in [`infrastructure/server-setup/group_vars/all.yml`](infrastructure/server-setup/group_vars/all.yml), applied by the provision playbook, and reviewed every minor release. |
| `workflow` | Version is hardcoded as an `env:`/input default inside a `.github/workflows/*.yml` file. Bumped on release branches (see `init-release.yml`'s sed step). |
| `package` | Version is a dependency/devDependency in [`package.json`](package.json). |
| `nvmrc` | Version is pinned in [`.nvmrc`](.nvmrc). |
| `external` | Not pinned in this repo at all — the running component self-updates or always installs `latest`/newest at provision time. Track the upstream project's releases directly. |
| `toolkit` | Owned and populated by the `opencrvs-core/packages/toolkit` package (a different repo) — not tracked here. |

## Dependencies

| Dependency | Tracked by | Description |
|---|---|---|
| Kubernetes (kubeadm/kubelet/kubectl) | ansible | Container orchestrator. Variable: `kubernetes_version`. Check: `kubectl version` / `kubeadm version` on a node. |
| Calico (CNI) | ansible | Pod networking plugin. Variable: `calico_version`. Check: `kubectl get tigerastatus` or image tag on `calico-node` pods (`kubectl get ds -n calico-system calico-node -o jsonpath='{.spec.template.spec.containers[0].image}'`). |
| Helm | ansible | Chart package manager (apt package). Variable: `helm_version`. Check: `helm version`. |
| helm-diff plugin | ansible | Helm plugin used for idempotent `kubernetes.core.helm` diffs. Variable: `helm_diff_plugin_version`. Check: `helm diff version`. |
| cert-manager | ansible | Issues/renews TLS certs in-cluster. Variable: `cert_manager_version`. Check: `helm list -n cert-manager`. |
| Actions Runner Controller (ARC) chart | ansible | Runs the Kubernetes-based self-hosted CI runner. Variable: `arc_chart_version`. Check: `helm list -n actions-runner-system`. |
| pgBackRest | ansible | Postgres differential/incremental backup tool, apt-pinned and held. Variable: `pgbackrest_version`. Check: `pgbackrest version` or `dpkg -s pgbackrest`. |
| OpenCRVS core & countryconfig images / chart | workflow | The application itself. Variables: `OPENCRVS_CHART_VERSION`, `core-image-tag`, `countryconfig-image-tag` in [`deploy-opencrvs.yml`](.github/workflows/deploy-opencrvs.yml). Check: `helm list -n <env-namespace>` for chart version, `kubectl get deploy -n <ns> -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'` for image tags. |
| Dependencies chart (Postgres/Elasticsearch/Redis/MinIO bundle) | workflow | Stateful backing services bundle. Variable: `DEPENDENCIES_CHART_VERSION` in [`deploy-dependencies.yml`](.github/workflows/deploy-dependencies.yml). Check: `helm list -n <env-namespace>`. |
| Traefik | workflow | Ingress controller / reverse proxy. Variable: `TRAEFIK_CHART_VERSION` in [`deploy-dependencies.yml`](.github/workflows/deploy-dependencies.yml). Check: `helm list -n <traefik-namespace>`. |
| GitHub-hosted runner OS | workflow | The VM image GitHub-hosted jobs run on (`approve`/setup jobs, not the self-hosted infra runners). Pinned per-workflow as `runs-on: ubuntu-26.04` (one outlier still uses `ubuntu-latest`). Check: `grep -rn "runs-on:" .github/workflows/`. |
| Pinned GitHub Actions (`actions/checkout`, `upload-artifact`, etc.) | workflow | Third-party/first-party Action versions used in CI steps. Check: `grep -rn "uses:" .github/workflows/`. |
| Node.js | nvmrc | Runtime for the `@opencrvs/infrastructure` CLI tooling. Pinned in `.nvmrc` (`package.json` `engines.node` should match). Check: `node -v`. |
| `@opencrvs/toolkit` | package | CLI used for `environment:init`/`upgrade`/etc. Check: `cat package.json | grep '"@opencrvs/toolkit"'` or `npm ls @opencrvs/toolkit`. |
| husky | package | Git hooks manager for this repo. Check: `npx husky --version`. |
| Kubernetes self-hosted runner image (`opencrvs-github-runner`) | ansible | CI runner container deployed via ARC, built by [`opencrvs/github-opencrvs-self-hosted-runner`](https://github.com/opencrvs/github-opencrvs-self-hosted-runner). Variable: `arc_opencrvs_runner_version`. Check running image: `kubectl get pods -n actions-runner-system -o jsonpath='{.items[*].spec.containers[*].image}'`. |
| Node-based self-hosted runner (`node-runner.sh`) | external | GitHub Actions runner binary installed as a systemd service on non-k8s nodes. Self-updates automatically before each job (see [`scripts/bootstrap/README.md`](scripts/bootstrap/README.md)) — not version-pinned in this repo. Check: GitHub UI → Settings → Actions → Runners, or `config.sh --version` / `journalctl -u 'actions.runner.*'` on the node. |
| metrics-server | external | Supplies `kubectl top`/HPA metrics. Always installs the latest GitHub release at provision time — not version-pinned. Check: `kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'`. |
| Workflow `environment:` dropdown options | toolkit | Populated by `opencrvs-core/packages/toolkit`, not by anything in this repo — track that package's version/behavior in `opencrvs-core` if the dropdown misbehaves. |

