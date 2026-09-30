#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS.

set -e

IMG="ubuntu:24.04"
NODES=("master" "worker")

for NODE in "${NODES[@]}"; do
  if orb list | grep -q "^$NODE "; then
    echo "Removing existing VM: $NODE"
    orb delete "$NODE" --force
  fi
done

sleep 10 # Wait few seconds for complete cleanup

# Create VMs
for NODE in "${NODES[@]}"; do
  orb create --arch arm64 "$IMG" "$NODE"
  orb start "$NODE"
done

for NODE in "${NODES[@]}"; do
  echo "apt-get -y install openssh-server" | orb exec -u root -m "$NODE" bash
  ssh-keygen -R $NODE.orb.local
done

# Provision user setup script
PROVISION_CMDS=$(cat <<'EOF'
sudo addgroup provision
sudo adduser --gecos "OpenCRVS Provisioning user" --disabled-password --ingroup provision provision
sudo usermod -aG sudo provision
echo 'provision ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers
EOF
)


# Run user creation on both VMs
for NODE in "${NODES[@]}"; do
  echo "Provisioning user on $NODE..."
  echo "$PROVISION_CMDS" | orb exec -u root -m "$NODE" bash
done


# SSH keygen on master
echo "Generating SSH key on master..."
orb exec -m master -u root bash -c '
mkdir -p /home/provision/.ssh
ssh-keygen -t rsa -f /tmp/ssh-key -N ""
cat /tmp/ssh-key.pub >> /home/provision/.ssh/authorized_keys
chmod 600 /home/provision/.ssh/authorized_keys
chown -R provision:provision /home/provision/.ssh
echo -e "\n\nThis is the SSH_KEY you add to Github Environments:\n\n"
cat /tmp/ssh-key
'

# Copy pub key from master to worker
echo "Copying pubkey to worker..."
PUBKEY=$(orb exec -m master cat /tmp/ssh-key.pub)
orb exec -m worker -u root bash -c "
mkdir -p /home/provision/.ssh
echo '$PUBKEY' >> /home/provision/.ssh/authorized_keys
chmod 600 /home/provision/.ssh/authorized_keys
chown -R provision:provision /home/provision/.ssh
"
# Get private key for ansible
mkdir -p .ssh
rm -f ./.ssh/ssh-key
PRIVATE_KEY=$(orb exec -u root -m master cat /tmp/ssh-key)
echo "$PRIVATE_KEY" > ./.ssh/ssh-key
chmod 400 ./.ssh/ssh-key
# Clean up private keys on master
orb exec -u root -m master rm -f /tmp/ssh-key /tmp/ssh-key.pub