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
▶️ Running User/Group setup script
-----------------------------------

"""

# --- USAGE ---
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --ssh-public-key     Add ssh public key to add to the user instead of generating a new key pair"
  echo "  -h, --help           Show this help message"
  echo ""
  exit 1
}

GROUP_NAME="provision"
USER_NAME="provision"

log() {
    echo -e "\n$1\n"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-public-key) SSH_PUBLIC_KEY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# --- Group checks and creation ---
# No GID is requested: the system assigns the first available one.
if getent group "$GROUP_NAME" > /dev/null; then
    log "✅ Group '$GROUP_NAME' already exists."
else
    log "🚀 Creating group: $GROUP_NAME with first available GID"
    sudo groupadd $GROUP_NAME
fi

# --- User checks and creation ---
# No UID is requested: the system assigns the first available one.
if getent passwd "$USER_NAME" > /dev/null; then
    log "✅ User '$USER_NAME' already exists."
else
    log "🚀 Creating user: $USER_NAME with first available UID and group: $GROUP_NAME"
    sudo useradd -g $GROUP_NAME -s /usr/bin/bash --create-home $USER_NAME
fi

# --- Sudo access checks and grant ---
# Check in /etc/sudoers and /etc/sudoers.d/
sudo_access=$(sudo grep -E '^provision\s+ALL=\(ALL(:ALL)?\)\s+NOPASSWD:\s+ALL' /etc/sudoers /etc/sudoers.d/* 2>/dev/null || true)
if [[ -n "$sudo_access" ]]; then
    log "✅ User '$USER_NAME' already has full sudo access."
else
    log "🚀 Granting full sudo access to user '$USER_NAME'..."
    log "${USER_NAME} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER_NAME > /dev/null
    sudo chmod 0440 /etc/sudoers.d/$USER_NAME
fi

sudo -u $USER_NAME mkdir -p /home/$USER_NAME/.ssh
sudo chmod 700 /home/$USER_NAME/.ssh
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    log "🚀 Adding provided SSH public key to user '$USER_NAME'..."
    echo "$SSH_PUBLIC_KEY" | sudo -u $USER_NAME tee -a /home/$USER_NAME/.ssh/authorized_keys > /dev/null
    sudo chmod 600 /home/$USER_NAME/.ssh/authorized_keys
else
    if [[ -f /home/$USER_NAME/.ssh/id_ed25519 ]]; then
        log "✅ SSH key pair for user '$USER_NAME' already exists."
    else
        log "🚀 Generating SSH key pair for user '$USER_NAME'..."
        sudo -u $USER_NAME mkdir -p /home/$USER_NAME/.ssh
        sudo -u $USER_NAME ssh-keygen -t ed25519 -f /home/$USER_NAME/.ssh/id_ed25519 -N "" -C "${USER_NAME}@$(hostname)"
    fi
    if sudo [ -f /home/$USER_NAME/.ssh/id_ed25519.pub ]; then
    log "
        ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ Store the following public key for later usage ⚠️ ⚠️ ⚠️ ⚠️ ⚠️
        ⚙️  $USER_NAME SSH key pair public key (add on worker nodes if needed):
        "
        sudo cat /home/$USER_NAME/.ssh/id_ed25519.pub
    else
        log "❌ FAIL: Unable to find or generate public key for user '$USER_NAME'."
        exit 1
    fi
fi
echo "✅ User/Group setup completed."
