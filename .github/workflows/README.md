## Update Workflow Environments

### Overview

This workflow keeps the list of environment options in your deployment-related workflows **automatically up-to-date**.  
It detects new or removed inventory files and updates the relevant workflow `.yml` files so their dispatch menus always offer the correct set of environments for manual runs.

---

### Trigger Conditions

- **Manual trigger:** from the GitHub Actions UI ("Run workflow")  
- **Automatic trigger:** on any branch push that modifies either  
  - Any inventory file at `environments/*/inventory.yml`
  - `.github/workflows/update-envs.yml` (the workflow itself)

---

### Job Details

**update-environments:**
- **runs-on:** `ubuntu-latest`

#### Steps

1. **Checkout repository**
   - Uses a token supplied via secret for proper repo access.

2. **Extract inventory names**
   - Dynamically lists all environment inventory YAML files (e.g., `environments/dev/inventory.yml`, `environments/qa/inventory.yml`).
   - Produces a list of environment names from the parent folder names.

3. **Update workflow files**
   - For each workflow (`provision.yml`, `deploy-dependencies.yml`, `deploy-opencrvs.yml`), uses [`yq`](https://github.com/mikefarah/yq) to update the `environment` options for workflow dispatch.
   - Now, the workflow UI always reflects what’s available based on inventory.

4. **Commit changes**
   - Configures GitHub Actions as the committer.
   - Adds and commits only the updated workflow YAML files.
   - Pushes the changes to the repo (if there were changes).

---

### Why Use This Workflow?

- **Automation & Consistency:** No one needs to manually edit workflow files whenever environments change.
- **Safety:** Prevents divergence between available inventories and actual dispatch UI options.
- **DevOps Friendly:** Works for multi-env setups (adding/removing inventories is all you have to do).

### Example

If you add `environments/staging/inventory.yml`, this workflow will update the dispatch menus for all related workflows to include `staging` as an option.


## Build and Push Runner Image Workflow

### Overview

This workflow automatically builds a Docker image for your GitHub Runner and pushes it to the **GitHub Container Registry (GHCR)** whenever code changes occur relating to the runner or its Dockerfile.

### Trigger

The workflow runs on each push to any branch when one of the following changes:
- `.github/workflows/build-and-push-runner-image.yml` (the workflow itself)
- `github-runner/Dockerfile` (the Dockerfile for your runner image)
- Any file under `github-runner/` (`github-runner/**`, optional for full context rebuilds)

### Workflow Steps

1. **Checkout code**  
   Uses the latest version of the repository to ensure the Docker build runs on up-to-date sources.

2. **Log in to GitHub Container Registry (GHCR)**  
   Authenticates Docker with the registry using `GITHUB_TOKEN` and the current actor.

3. **Build Docker Image**  
   - The image is built from `github-runner/Dockerfile`, using the `github-runner/` directory as the build context.
   - The image tag is set to the short commit hash (`${COMMIT_HASH}`), ensuring uniquely versioned images for each commit.

4. **Push Docker Image**  
   - Pushes the new image to GHCR with the commit hash tag.
   - Also tags and pushes the image as `latest` for convenience.

### Tagging Convention

- `${COMMIT_HASH}`: Shortened commit SHA of the current build (7 characters).
- `latest`: The most recent build, always overwritten.


---

**Note:**  
If you wish to build images from another context or change the registry location, adjust the workflow accordingly.

## Release Helm Charts Workflow

> NOTE: In the future charts will be moved into separate repository

### Overview

This workflow automates the packaging and publishing of Helm charts to the GitHub Container Registry (**GHCR**) for the repository.  
It ensures that every change to the charts directory or to the workflow file itself will result in updated, published Helm chart packages.

---

### Triggers

- **Manual dispatch:** via GitHub Actions UI ("Run workflow").
- **Push events to `develop` branch:**  
  When:
  - Any files under `charts/**` change
  - The workflow file `.github/workflows/publish-charts.yml` changes

---

### Workflow Steps

1. **Checkout repository**
   - Checks out all sources (full history) so charts and versioning are available for Helm packaging.

2. **Package Helm charts**
   - Creates a `packages` directory.
   - Iterates over each chart inside the `charts/` directory.
   - Runs `helm package` to create chart packages (`.tgz` files) for each chart and stores them in `packages/`.

3. **Publish Helm charts**
   - Logs into GHCR using the provided registry token (`PACKAGE_GITHUB_TOKEN`).
   - Pushes each packaged chart to `ghcr.io/opencrvs` using `helm push` in OCI registry mode.

---

### Publishing Details

- Charts are pushed to [ghcr.io/opencrvs](https://ghcr.io/opencrvs) as Open Container Initiative (OCI) artifacts.
- Authentication is handled using a dedicated GitHub token (`PACKAGE_GITHUB_TOKEN`) for secure registry access.

---

### Usage

- To release a chart update:  
  Push changes to a Helm chart directory inside `charts/` to the `develop` branch or manually invoke the workflow in the Actions tab.
- New chart packages will be available in GHCR moments after successful workflow completion.

---

### Permissions

- Requires `contents: write` to push updates for chart metadata and release publishing.

---

### Notes

- Make sure all charts follow proper Helm conventions and versioning.
- The workflow expects the runner to have Helm installed (GitHub’s Ubuntu runners do by default).
- Registry authentication uses the username `adskyiproger`; update as needed for your organization.

---

## Nightly E2E Workflow

### Overview

`deploy-and-e2e.yml` runs the OpenCRVS e2e suite against **`e2e.opencrvs.dev`** — the *nightly environment*, the one persistent deployment shared by QA and CI. One scheduled run per day at **00:00 UTC** wipes the environment, re-seeds it, deploys the current `develop` image and runs both test suites: the standard suite and the `qa-testrail-testcases` regression suite.

It replaces a redeploy-and-retest on every push to `develop`. Every PR already runs the full suite on its own ephemeral stack minutes before merge, so those runs mostly re-confirmed what had just been confirmed, ~10 times a day, while wiping the environment under QA 89% of the time inside the working day.

The accepted cost is stated plainly: **merge-order breakage — two PRs green apart, red together — now surfaces within 24 hours rather than within one.**

---

### Triggers

- **`schedule`** — 00:00 UTC daily. The only automatic trigger.
- **`workflow_dispatch`** — a manual run, which may opt out of the regression suite to reproduce a standard-suite failure faster.
- **`repository_dispatch`** (`run_e2e`) — retained for external callers.

The cron runs **whether or not `develop` moved**. A re-run of an identical image tag is a pure flake measurement, and — because the run reports exactly one Slack message a day — a skipped day would make a missing message ambiguous between "nothing merged" and "GitHub auto-disabled the schedule after 60 days of repository inactivity".

---

### Reporting

One Slack message per run, to the existing e2e results channel (`C08FCLKER8X`) where develop e2e results already land, rendered from the 20 per-shard CTRF reports merged in the `notify-slack` job:

- **Success** carries the passed count, wall-clock, how many regression specs ran, and how many tests were rescued on retry. It is posted deliberately — at one message a day, the **absence** of a message is the signal that the schedule has died.
- **Failure** names every failing spec by full repo-relative path, split into **regression-suite** and **standard-suite** groups. The split routes the failure before anyone opens the run: a `qa-testrail-testcases/` failure is QA's call between a test-case update and a product bug, anything else is a dev regression.
- **A shard that reported nothing** is a line of its own, distinct from test failures. This — not the 40-minute job timeout — is what stops a partial run reading as green: a shard killed mid-suite writes no CTRF at all, so it merges one report fewer and its failures would otherwise vanish.
- **Cancellation** is reported too. It is rare now that nothing races the cron, which is what makes it worth saying.

The renderer is `scripts/nightly-notify/`, kept out of the YAML because its most important paths are ones a healthy run never produces. It runs against fixtures with no install step:

```bash
yarn test                                    # the failure, missing-shard and flake paths
node scripts/nightly-notify/main.mjs ./some-downloaded-artifacts   # render a real run
```

---

### Who owns a red nightly

**The QA team owns it**, and decides whether a failure is a test-case update or a product bug. A release manager reading the channel should be able to tell from the daily message whether `develop` is green before cutting a release, and should be able to assume a red nightly has an owner.

**Flake policy is fix, not quarantine.** A red nightly is fixed or filed as a bug. `test.skip` is not a sanctioned response to one — the repository already carries ~17 permanently skipped tests with empty bodies, which is the outcome this rule exists to stop growing. Retries rescue something on 93% of green runs, so the ranked flake backlog built from the uploaded CTRF reports is the useful artifact, not a per-run flake alarm.

---

### Refreshing the environment on demand

The nightly leaves the environment in its **post-run state** — no teardown, no re-seed. That is deliberate: triage needs the failing state intact, and a post-run re-seed would destroy the evidence before anyone saw it.

So the environment can be up to ~24 hours stale. To pull it to current `develop`, dispatch **"03. Deploy OpenCRVS"** with `environment: e2e`. This does not reset data.

That dispatch is guarded twice, because concurrency alone is not enough:

- `concurrency: deploy-<environment>` serialises deploys against deploys, and **queues** rather than cancels — a deploy killed mid-flight leaves a half-applied Helm release.
- A **pre-flight refusal** covers the rest: during the ~19-minute test fan-out the nightly holds no job in that group at all, so the `guard-e2e-suite` job fails fast and names the run in flight rather than letting a refresh swap the deployment out from under a live suite. Wait for it, or cancel it, then dispatch again.

---

### Runtime bounds

- `timeout-minutes: 40` on each shard job, which is roughly twice the worst healthy shard ever measured. The comment on that setting in `deploy-and-e2e.yml` carries the distribution it was derived from and why the headroom is load-bearing rather than generic — read it there before changing the value, not here.
- The shard layout lives in one place, the `plan` job. The matrix, the `--shard=<n>/<count>` argument and the notify job's shard-set check all derive from it.

---

### Note on the numbers

Every measurement above was taken **before the regression suite had ever run in CI**. `retries` is the exposed one: no rescue in a month needed a third attempt, but that is a statement about standard-suite specs, and a regression spec is long and single-test, so a flake near the end re-runs the whole flow. **Revisit `retries` after two weeks of nightly data**, treating a regression spec rescued on attempt 3 as the signal rather than as flake to absorb. The per-shard CTRF artifacts are what make that visible.
