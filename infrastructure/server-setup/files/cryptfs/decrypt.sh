#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS.

# NOTE: We recommend that the encryption key is served via a secure API from a Hardware Security Module
# This script unlocks and mounts the encrypted OpenCRVS data filesystem.
# It loads the disk encryption password from one of two sources:
# - For environments without a backup server, it reads a local key file on the Kubernetes master node.
# - For environments with a backup server, it downloads the encrypted key file over SSH, decrypts it
#   with the local backup encryption passphrase, and reads the decrypted disk encryption password.
# After the password is loaded, the script attaches the encrypted data file to a loop device,
# opens the LUKS mapping, and mounts it to the configured data directory.

# defaults, use options to override
FS_FILE=/cryptfs_file_sparse.img  # -f, --file
MOUNT_PATH=/data                  # -m, --mount
DEV_MAP_NAME=cryptfs              # -n, --name
                                  # -key, --encryptionKeyFilepath (required - path to a file containing the decryption passphrase in the format DISK_ENCRYPTION_KEY=XXXX.)
# Path to private key file for the remote backup server, used to download the encrypted disk encryption key.
REMOTE_SSH_PRIVATE_KEY=/root/.ssh/backup_host_private_key
# Path to file containing encryption passphrase to decrypt the encrypted disk encryption key.
REMOTE_FILE_ENCRYPTION_KEY_PATH=/root/backup-encryption-passphrase.txt

# options
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
  -f | --file )
    shift; FS_FILE=$1
    ;;
  -m | --mount )
    shift; MOUNT_PATH=$1
    ;;
  -n | --dev-map-name )
    shift; DEV_MAP_NAME=$1
    ;;
  -key | --encryptionKeyFilepath )
    shift; ENCRYPTION_KEY_FILE_PATH=$1
    ;;
  -remote-ssh-private-key | --remoteSshPrivateKeyFilepath )
    shift; REMOTE_SSH_PRIVATE_KEY_FILE_PATH=$1
    ;;
  -remote-file-encryption-key | --remoteFileEncryptionKeyFilepath )
    shift; REMOTE_FILE_ENCRYPTION_KEY_PATH=$1
    ;;
  -remote | --remoteEncryptedKeyFilepath )
    shift; REMOTE_ENCRYPTED_KEY_FILE_PATH=$1
    ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

if [[ -n "$REMOTE_ENCRYPTED_KEY_FILE_PATH" || -n "$REMOTE_FILE_ENCRYPTION_KEY_PATH" || -n "$REMOTE_SSH_PRIVATE_KEY" ]]; then
  if [[ -z "$REMOTE_ENCRYPTED_KEY_FILE_PATH" || -z "$REMOTE_FILE_ENCRYPTION_KEY_PATH" || -z "$REMOTE_SSH_PRIVATE_KEY" ]]; then
    echo "ERROR: Remote disk encryption key requires -remote, -remote-file-encryption-key, and -remote-ssh-private-key."
    exit 1
  fi

  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT

  ENCRYPTED_KEY_FILE_PATH="$TMP_DIR/disk-encryption-key.txt.enc"
  ENCRYPTION_KEY_FILE_PATH="$TMP_DIR/disk-encryption-key.txt"

<<<<<<< HEAD
  if ! scp -i "$REMOTE_SSH_PRIVATE_KEY" \
=======
  if ! scp -i "$REMOTE_PRIVATE_KEY_FILE_PATH" \
    -o BatchMode=yes \
>>>>>>> 5dee1b6 (testing)
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=30 \
    "$REMOTE_ENCRYPTED_KEY_FILE_PATH" \
    "$ENCRYPTED_KEY_FILE_PATH"; then
    echo "ERROR: Failed to download disk encryption key from backup server."
    exit 1
  fi

  if ! openssl enc -d -aes-256-cbc -pbkdf2 \
    -pass file:"$REMOTE_FILE_ENCRYPTION_KEY_PATH" \
    -in "$ENCRYPTED_KEY_FILE_PATH" \
    -out "$ENCRYPTION_KEY_FILE_PATH"; then
    echo "ERROR: Failed to decrypt disk encryption key from backup server."
    exit 1
  fi
elif [[ -z "$ENCRYPTION_KEY_FILE_PATH" ]]; then
  echo "ERROR: Disk encryption key file path is required. Use -key or --encryptionKeyFilepath."
  exit 1
fi

if [[ ! -f "$ENCRYPTION_KEY_FILE_PATH" ]]; then
  echo "ERROR: Disk encryption key file does not exist: $ENCRYPTION_KEY_FILE_PATH"
  exit 1
fi

DISK_ENCRYPTION_KEY=$(sed -n 's/^DISK_ENCRYPTION_KEY=//p' "$ENCRYPTION_KEY_FILE_PATH" | head -1)
if [[ -z "$DISK_ENCRYPTION_KEY" ]]; then
  echo "ERROR: Disk encryption key file must contain DISK_ENCRYPTION_KEY."
  exit 1
fi

# create a loop device from the data file if it doesn't already exist
LOOP_DEVICE=$(losetup -j "$FS_FILE" | awk '{print substr($1, 1, length($1)-1)}' | head -1)
echo "$LOOP_DEVICE"
if [[ -z "$LOOP_DEVICE" ]]; then
  if ! LOOP_DEVICE=$(losetup --find --show "$FS_FILE"); then
    echo "ERROR: Failed to create loop device for $FS_FILE."
    exit 1
  fi
  echo "Created new loop device $LOOP_DEVICE"
else
  echo "Using existing loop device $LOOP_DEVICE"
fi

# open the LUKS device and set a mapping name
if cryptsetup status "$DEV_MAP_NAME" >/dev/null 2>&1; then
  echo "Using existing LUKS device mapping $DEV_MAP_NAME"
else
  if ! echo "$DISK_ENCRYPTION_KEY" | cryptsetup -d - luksOpen "$LOOP_DEVICE" "$DEV_MAP_NAME"; then
    echo "ERROR: Failed to open LUKS device mapping $DEV_MAP_NAME."
    exit 1
  fi
fi

# mount the device to a folder
mkdir -p "$MOUNT_PATH"
if mountpoint -q "$MOUNT_PATH"; then
  echo "$MOUNT_PATH is already mounted"
else
  if ! mount "/dev/mapper/$DEV_MAP_NAME" "$MOUNT_PATH"; then
    echo "ERROR: Failed to mount /dev/mapper/$DEV_MAP_NAME to $MOUNT_PATH."
    exit 1
  fi
fi
