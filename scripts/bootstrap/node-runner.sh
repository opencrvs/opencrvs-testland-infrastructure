#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS.

printf """
-----------------------------------
▶️ Running Node runner setup script
-----------------------------------
"""

set -o errexit      # Stop on error (like `-e`)
set -o nounset      # Stop on unset vars (like `-u`)
set -o pipefail     # Fail on first failed command in a pipeline
set -o errtrace     # Trap ERR in functions and subshells

trap 'echo "❌ Script failed on line $LINENO with exit code $?"' ERR

# --- USAGE ---
usage() {
  echo """
Usage: $0 [OPTIONS]

Options:
  --owner         GitHub org or username (required)
  --repo          GitHub repository name (required)
  --env           Infrastructure environment name(s) comma-separated (required)
                  Runner will be used to provision infrastructure for these envs
                  For example: dev,qa,staging or prod
  --token         GitHub PAT or registration token (required)
  --name          Runner name (default: <hostname>-runner)
  --dir           Runner install directory (default: /opt/github-runner)
  -h, --help      Show this help message
"""
  exit 1
}

# --- PARSE OPTIONS ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) GITHUB_OWNER="$2"; shift 2 ;;
    --repo) REPO_NAME="$2"; shift 2 ;;
    --token) GITHUB_TOKEN="$2"; shift 2 ;;
    --dir) RUNNER_DIR="$2"; shift 2 ;;
    --env) ENV="$2"; shift 2 ;;
    --runas-user) RUNAS_USER="$2"; shift 2 ;;
    --runas-group) RUNAS_GROUP="$2"; shift 2 ;;
    --name) RUNNER_NAME="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# --- INTERACTIVE PROMPTS (IF NOT SET) ---
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp "GitHub owner (or org): " GITHUB_OWNER
[[ -z "${REPO_NAME:-}" ]] && read -rp "Repository name: " REPO_NAME
[[ -z "${ENV:-}" ]] && read -rp "Infrastructure environment name(s): " ENV
[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub token (no echo): " GITHUB_TOKEN && echo

# --- OPTIONAL DETERMINE (IF NOT SET) ---
# Runner install directory
RUNNER_DIR=${RUNNER_DIR:-"/opt/github-runner"}
# Runner name
[[ -z "${RUNNER_NAME:-}" ]] && RUNNER_NAME="$(hostname)-runner"
# Runner labels
LABELS="self-hosted,linux,node,${ENV}"
# Runner user and group
RUNAS_USER="${RUNAS_USER:-provision}"
RUNAS_GROUP="${RUNAS_GROUP:-provision}"


# --- DETERMINE REGISTRATION URL ---
REG_URL="https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}/actions/runners/registration-token"
RUNNER_SCOPE="https://github.com/${GITHUB_OWNER}/${REPO_NAME}"

# --- INSTALL DEPENDENCIES ---
echo "[+] Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y curl jq tar ansible

# --- CREATE RUNNER DIR ---
sudo mkdir -p "${RUNNER_DIR}"
sudo chown $RUNAS_USER:$RUNAS_GROUP "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

# --- DOWNLOAD RUNNER ---
if [[ ! -f "runner.tar.gz" ]]; then
  echo "[+] Downloading GitHub runner..."

  RUNNER_LATEST_URL=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
    | jq -r '.assets[] | select(.name | test("linux-x64")) | .browser_download_url')

  if [[ -z "$RUNNER_LATEST_URL" ]]; then
    echo "❌ Failed to fetch GitHub runner URL. Check your internet connection and 'jq'."
    exit 1
  fi
  # FIXME:Fails with permission denied if run as non-root without sudo, so we use sudo for the download step
  echo "[+] Download URL: $RUNNER_LATEST_URL into folder $(pwd)"
  DOWNLOAD_OK=false
  for attempt in 1 2 3; do
    if sudo -u $RUNAS_USER curl -fL "$RUNNER_LATEST_URL" -o runner.tar.gz; then
      DOWNLOAD_OK=true
      break
    fi
    echo "⚠️  Download attempt $attempt failed, retrying..."
    [ "$attempt" -lt 3 ] && sleep 3
  done
  if [ "$DOWNLOAD_OK" != "true" ]; then
    echo "❌ Failed to download runner archive."
    exit 1
  fi
else
  echo "[i] runner.tar.gz already exists. Skipping download."
fi

echo "[+] Extracting runner..."
sudo -u $RUNAS_USER tar xzf runner.tar.gz
echo "[+] Setting permissions... `pwd`"
sudo chown -R $RUNAS_USER:$RUNAS_GROUP .
# --- GET REGISTRATION TOKEN ---
echo "[+] Requesting registration token..."
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "${REG_URL}" | jq -r .token)

# --- CONFIGURE RUNNER ---
echo "[+] Configuring runner ${RUNNER_NAME}..."
sudo -u $RUNAS_USER ./config.sh \
  --unattended \
  --url "${RUNNER_SCOPE}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${LABELS}" \
  --work "_work"

# --- SETUP SYSTEMD SERVICE ---
echo "[+] Installing systemd service..."

sudo ./svc.sh install provision

# Fix service to run as specific user/group
SERVICE_FILE_PATH=$(ls /etc/systemd/system/actions.runner.*.service 2>/dev/null | head -n1)
if [[ -n "$SERVICE_FILE_PATH" ]]; then
  echo "[+] Updating systemd unit to run as ${RUNAS_USER}:${RUNAS_GROUP}..."
  sudo sed -i "s/^User=.*/User=${RUNAS_USER}/" "$SERVICE_FILE_PATH"
  sudo sed -i "s/^Group=.*/Group=${RUNAS_GROUP}/" "$SERVICE_FILE_PATH"
  sudo systemctl daemon-reload
else
  echo "⚠️ Could not find service file automatically — please verify installation."
fi

sudo ./svc.sh start

echo "✅ Runner '${RUNNER_NAME}' is installed and started!"
