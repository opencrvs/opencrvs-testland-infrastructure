#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS.

#!/bin/bash
set -e

IMG="24.04"
NODES=("master" "worker")

# Your local public key file - prefer common default key names, otherwise
# fall back to the first .pub file found in ~/.ssh
LOCAL_PUBKEY_FILE=""
for CANDIDATE in id_ed25519.pub id_ecdsa.pub id_rsa.pub; do
  if [[ -f "$HOME/.ssh/$CANDIDATE" ]]; then
    LOCAL_PUBKEY_FILE="$HOME/.ssh/$CANDIDATE"
    break
  fi
done

if [[ -z "$LOCAL_PUBKEY_FILE" ]]; then
  LOCAL_PUBKEY_FILE=$(find "$HOME/.ssh" -maxdepth 1 -name '*.pub' -print -quit)
fi

# Check if public key exists
if [[ -z "$LOCAL_PUBKEY_FILE" || ! -f "$LOCAL_PUBKEY_FILE" ]]; then
  echo "No local SSH public key found in $HOME/.ssh"
  echo "Generate one"
  exit 1
fi

echo "Using local SSH public key: $LOCAL_PUBKEY_FILE"

LOCAL_PUBKEY=$(cat "$LOCAL_PUBKEY_FILE")

for NODE in "${NODES[@]}"; do
  if multipass list | grep -q "^$NODE "; then
    echo "Removing existing VM: $NODE"
    multipass delete "$NODE"
    multipass purge
  fi
done

# Create VMs
for NODE in "${NODES[@]}"; do
  multipass launch --name "$NODE" --cpus 2 --memory 2G --disk 15G "$IMG"
done

# Provision user setup script
PROVISION_CMDS=$(cat <<'EOF'
sudo addgroup --gid 1100 provision
sudo adduser --gecos "OpenCRVS Provisioning user" --disabled-password --uid 1100 --gid 1100 provision
sudo usermod -aG sudo provision
echo 'provision ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers
EOF
)

# Run user creation on both VMs
for NODE in "${NODES[@]}"; do
  echo "Provisioning user on $NODE..."
  echo "$PROVISION_CMDS" | multipass exec "$NODE" -- bash
done

# SSH keygen on master
echo "Generating SSH key on master..."
multipass exec master -- bash -c '
sudo -u provision mkdir -p /home/provision/.ssh
sudo ssh-keygen -t rsa -f /tmp/ssh-key -N ""
sudo cat /tmp/ssh-key.pub | sudo tee -a /home/provision/.ssh/authorized_keys > /dev/null
sudo chmod 600 /home/provision/.ssh/authorized_keys
sudo chown -R provision:provision /home/provision/.ssh
'

# Copy pub key from master to worker
echo "Copying pubkey to worker..."
PUBKEY=$(multipass exec master -- cat /tmp/ssh-key.pub)
multipass exec worker -- bash -c "
sudo -u provision mkdir -p /home/provision/.ssh
sudo -u provision bash -c 'echo \"$PUBKEY\" >> /home/provision/.ssh/authorized_keys'
sudo chmod 600 /home/provision/.ssh/authorized_keys
sudo chown -R provision:provision /home/provision/.ssh
"

# Copy local public key to all nodes and adding node IPs to known_hosts 
for NODE in "${NODES[@]}"; do
  echo "Setting up SSH key on $NODE..."
  multipass exec "$NODE" -- bash -c "
    echo \"$LOCAL_PUBKEY\" | sudo -u provision tee -a /home/provision/.ssh/authorized_keys > /dev/null
  "
  IP=$(multipass info "$NODE" | grep "IPv4:" | awk '{print $2}')
  echo "Adding $NODE ($IP) to known_hosts..."
  ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null
done

# Get private key for ansible
mkdir -p .ssh
multipass exec master -- sudo chmod 444 /tmp/ssh-key
multipass transfer master:/tmp/ssh-key ./.ssh/ssh-key
chmod 400 ./.ssh/ssh-key
# Clean up private keys on master
multipass exec master -- sudo rm -f /tmp/ssh-key /tmp/ssh-key.pub

# Update inventory file with new IP addresses
echo "Updating inventory file with new IP addresses..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/local.linux.yml.template" "$SCRIPT_DIR/local.linux.yml"
INVENTORY_FILE="$SCRIPT_DIR/local.linux.yml"

MASTER_IP=$(multipass list | awk '/master/ {print $3}')
WORKER_IP=$(multipass list | awk '/worker/ {print $3}')

if [[ -z "$MASTER_IP" || -z "$WORKER_IP" ]]; then
  echo "Failed to retrieve IP addresses from multipass."
  exit 1
fi

sed -i "s/ansible_host: '.*'/ansible_host: '$MASTER_IP'/" "$INVENTORY_FILE"
sed -i "0,/ansible_host: '$MASTER_IP'/!s/ansible_host: '.*'/ansible_host: '$WORKER_IP'/" "$INVENTORY_FILE"

echo "Inventory updated successfully."