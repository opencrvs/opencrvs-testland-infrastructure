#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS.

# Script to bootstrap a server as OpenCRVS infrastructure node
# - Creates 'provision' user if not exists
# - Installs and configures GitHub Actions runner to connect to the specified repos
# - Can be used for both master and worker nodes
set -e

# Configurable params
PROVISION_UID=1000
PROVISION_GID=1000
PROVISION_USER="provision"
PROVISION_GROUP="provision"
MIN_UBUNTU_VERSION="24.04"

# --- Helper Functions --- #
abort() { echo "ERROR: $1"; exit 1; }

# --- USAGE ---
usage() {
  echo """
Usage: $0 [OPTIONS]

Options required for master node:
    --owner           GitHub org or username (required)
    --repo            GitHub repository name (required)
    --env             Infrastructure environment name(s) comma-separated (required)
                        Runner will be used to provision infrastructure for these envs
                        For example: dev,qa,staging or prod
    --token           GitHub PAT or registration token (required)
    --enable-runner   Whether to enable the runner after installation (default: true)
Options Required for worker node:
    --ssh-public-key  Add ssh public key to add to the user instead of generating a new key pair
Help:
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
    --env) ENV="$2"; shift 2 ;;
    --enable-runner) ENABLE_RUNNER=true; shift ;;
    --ssh-public-key) SSH_PUBLIC_KEY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

check_ubuntu_version() {
    echo "Checking Ubuntu version..."
    UBUNTU_VERSION=$(lsb_release -rs)
    if [ "$UBUNTU_VERSION" != "$MIN_UBUNTU_VERSION" ]; then
      abort "Ubuntu $MIN_UBUNTU_VERSION is required, found $UBUNTU_VERSION"
    fi
    echo "Ubuntu version OK."
}

curl_check_url() {
    local url="$1"
    local http_code
    local attempt

    for attempt in 1 2 3; do
        http_code="$(curl \
            --silent \
            --location \
            --head \
            --max-time 10 \
            --output /dev/null \
            --write-out "%{http_code}" \
            "$url" || true)"

        # 000 means curl could not connect / DNS failed / TLS failed / timed out.
        if [ "$http_code" != "000" ]; then
            return 0
        fi

        [ "$attempt" -lt 3 ] && sleep 3
    done

    return 1
}

check_internet() {
    local urls=(
        "https://raw.githubusercontent.com/"
        "https://get.helm.sh"
        "https://pkgs.k8s.io"
        "https://archive.ubuntu.com"
        "https://changelogs.ubuntu.com"
        "https://hub.docker.com"
        "https://auth.docker.io"
        "https://registry-1.docker.io"
        "https://download.docker.com"
        "https://sentry.io"
        "https://fonts.gstatic.com"
        "https://storage.googleapis.com"
        "https://fonts.googleapis.com"
        "https://github.com"
        "https://acme-v02.api.letsencrypt.org"
        "https://registry.npmjs.org"
        "https://registry.yarnpkg.com"
        "https://eu.ui-avatars.com"
    )

    local failed=0

    echo "Testing outbound HTTPS connectivity..."
    echo

    printf "%-40s %-10s\n" "URL" "STATUS"
    printf "%-40s %-10s\n" "----------------------------------------" "----------"

    for url in "${urls[@]}"; do
        if curl_check_url "$url"; then
            printf "%-45s %-10s\n" "$url" "OK"
        else
            printf "%-45s %-10s\n" "$url" "FAILED"
            failed=1
        fi
    done

    echo

    if [ "$failed" -ne 0 ]; then
        abort "Internet connectivity check failed. Some required endpoints are unreachable."
    fi

    echo "Internet connectivity OK."
}

# ---- MAIN ---- #

echo "Running basic checks..."
check_ubuntu_version
check_internet

echo "Downloading dependencies..."
sudo rm -f /tmp/create-provision-user.sh
curl -sS https://raw.githubusercontent.com/opencrvs/infrastructure/develop/scripts/bootstrap/create-provision-user.sh -o /tmp/create-provision-user.sh
chmod +x /tmp/create-provision-user.sh
sudo rm -f /tmp/node-runner.sh
curl -sS https://raw.githubusercontent.com/opencrvs/infrastructure/develop/scripts/bootstrap/node-runner.sh -o /tmp/node-runner.sh
chmod +x /tmp/node-runner.sh

/tmp/create-provision-user.sh --ssh-public-key "$SSH_PUBLIC_KEY"
[ "x$ENABLE_RUNNER" == "xtrue" ] && /tmp/node-runner.sh --env "${ENV}" \
                                                        --owner "${GITHUB_OWNER}" \
                                                        --repo "${REPO_NAME}" \
                                                        --token "${GITHUB_TOKEN}"

echo ""
sudo [ -f "/home/$PROVISION_USER/.ssh/id_ed25519.pub" ] && \
echo "
⚠️ ⚠️ ⚠️ ⚠️ ⚠️ Store the following public key for later usage ⚠️ ⚠️ ⚠️ ⚠️ ⚠️
⚙️  $PROVISION_USER SSH key pair public key (add on worker nodes if needed):
" && \
sudo cat /home/$PROVISION_USER/.ssh/id_ed25519.pub
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Node bootstrap complete for $(hostname)."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
