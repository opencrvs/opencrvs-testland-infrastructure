# How to deploy self-hosted runner on Node?

> **NOTE:** Don't use node-runner for Cloud infrastructure.

Runner installation is managed by [`opencrvs-bootstrap.sh`](./opencrvs-bootstrap.sh)

Node runner is used for running GitHub Actions provision workflow to deploy Kubernetes cluster and configure node (VM) for OpenCRVS.


Run following command:
```
curl -s https://raw.githubusercontent.com/opencrvs/infrastructure/develop/scripts/bootstrap/node-runner.sh -o runner.sh && bash runner.sh
```

## Upgrades

`node-runner.sh` installs the runner via `config.sh` without `--disableupdate`, so the
GitHub Actions runner service auto-updates itself: each time it connects to pick up a job,
it checks for a newer runner release and applies it before running the job. No manual
upgrade step is required for the runner binary itself.

Re-running `node-runner.sh` is **not** an upgrade path — it skips the download step
entirely if `runner.tar.gz` already exists in the runner directory (default
`/opt/github-runner`), so it will not fetch a newer release. To force a clean
reinstall (e.g. to change runner labels or recover from a broken install), remove the
runner directory first, then re-run the script:
```
sudo systemctl stop actions.runner.*
sudo rm -rf /opt/github-runner
curl -s https://raw.githubusercontent.com/opencrvs/infrastructure/develop/scripts/bootstrap/node-runner.sh -o runner.sh && bash runner.sh
```
