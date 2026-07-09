#!/bin/bash
###########################################################################
# This script is used to convert OpenCRVS backup made by OS cronjob (docker swarm)
# into a format that can be used by the Kubernetes cronjob.
# NOTE: USE THIS SCRIPT WITH CAUTION
# HOW TO USE:
# 1. Put the script in the backup user home directory (e.g. /home/backup)
# 2. Set the following environment variables:
#    - PASSPHRASE: The passphrase used to encrypt the backup file.
#    - LABEL: The label of the backup in the format YYYY-MM-DD.
#    - SWARM_BACKUP_ENC_FILE: The full path to the encrypted backup file
#    - K8S_BACKUP_DIR: (Optional) The directory where the converted backup files will be stored. 
#      Default is /home/backup/k8s-backup. Please adjust to your Kubernetes cronjob backup directory.
# 3. Run the script from backup user home directory: ./convert-backup.sh
###########################################################################

##################################
# Required variables
: "${PASSPHRASE:?Must set PASSPHRASE}"
: "${LABEL:?Must set LABEL in format YYYY-MM-DD}"
: "${SWARM_BACKUP_ENC_FILE:?Set full path to encrypted file variable SWARM_BACKUP_ENC_FILE}"
##################################

##################################
# Optional variables
K8S_BACKUP_DIR=${K8S_BACKUP_DIR-/home/backup/k8s-backup}
##################################

NEW_BACKUP_DIR=${K8S_BACKUP_DIR}/${LABEL}
# SWARM_BACKUP_ENC_FILE="${LABEL}.tar.gz.enc"
SWARM_BACKUP_FILE="${SWARM_BACKUP_ENC_FILE%.enc}"
BACKUP_RAW_FILES_DIR="$(dirname "$SWARM_BACKUP_FILE")"
EXTRACT_DIR="${BACKUP_RAW_FILES_DIR}/extract"
echo "Decrypting $SWARM_BACKUP_ENC_FILE to $SWARM_BACKUP_FILE"
openssl enc -d \
  -aes-256-cbc \
  -salt \
  -pbkdf2 \
  -in "$SWARM_BACKUP_ENC_FILE" \
  -out "$SWARM_BACKUP_FILE" \
  -pass "pass:$PASSPHRASE"
mkdir -p "$EXTRACT_DIR"

echo "Extracting archive $SWARM_BACKUP_FILE to $EXTRACT_DIR"
tar -xzf "$SWARM_BACKUP_FILE" -C "$EXTRACT_DIR"
echo "Remove elasticsearch directory"
rm -rf "$EXTRACT_DIR/elasticsearch"

echo "Package influxdb"
tar -czf "$BACKUP_RAW_FILES_DIR/influxdb_backup_${LABEL}.tar.gz" \
    -C "$BACKUP_RAW_FILES_DIR/extract/influxdb" \
    .
echo "Package minio"
echo "1. Extracting ocrvs-${LABEL}.tar.gz from $BACKUP_RAW_FILES_DIR/extract/minio"
mkdir "$BACKUP_RAW_FILES_DIR/extract/minio-tmp"
tar xf "$BACKUP_RAW_FILES_DIR/extract/minio/ocrvs-${LABEL}.tar.gz" -C "$BACKUP_RAW_FILES_DIR/extract/minio-tmp"
echo "2. Packaging minio"
tar -czf "$BACKUP_RAW_FILES_DIR/minio_backup_${LABEL}.tar.gz" \
    -C "$BACKUP_RAW_FILES_DIR/extract/minio-tmp" \
    .
echo "Package mongo"
echo "1. Rename extracted mongo database files to remove the label suffix"
for DB in $(ls -1 "$BACKUP_RAW_FILES_DIR/extract/mongo"); do
    NEW_ARCHIVE_NAME="${DB/-${LABEL}/}"
    echo "- $DB -> ${NEW_ARCHIVE_NAME}"
    mv "$BACKUP_RAW_FILES_DIR/extract/mongo/$DB" "$BACKUP_RAW_FILES_DIR/extract/mongo/${NEW_ARCHIVE_NAME}"
done
echo "2. Packaging mongo"
tar -czf "$BACKUP_RAW_FILES_DIR/mongo_backup_${LABEL}.tar.gz" \
    -C "$BACKUP_RAW_FILES_DIR/extract/mongo" \
    .
mkdir -p $NEW_BACKUP_DIR
for BACKUP_FILE in influxdb_backup_${LABEL}.tar.gz minio_backup_${LABEL}.tar.gz mongo_backup_${LABEL}.tar.gz; do
    echo "Encrypting $BACKUP_FILE"
    openssl enc -aes-256-cbc -salt -pbkdf2 -in ${BACKUP_RAW_FILES_DIR}/${BACKUP_FILE} -out ${BACKUP_RAW_FILES_DIR}/${BACKUP_FILE}.enc -pass pass:$PASSPHRASE
    echo "Moving $BACKUP_FILE.enc to $NEW_BACKUP_DIR"
    mv "$BACKUP_RAW_FILES_DIR/$BACKUP_FILE.enc" $NEW_BACKUP_DIR
done
