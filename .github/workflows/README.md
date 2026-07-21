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
