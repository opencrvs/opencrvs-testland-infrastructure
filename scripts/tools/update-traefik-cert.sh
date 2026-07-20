#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS

# Description:
# Checks if the TLS certificate has changed,
# updates the Kubernetes traefik-cert secret if needed, 
# and automatically restores the previous version if the update fails.

set -euo pipefail

LOG_MODE="${LOG_MODE:-auto}"  # auto | stdout | syslog

# Path to the new certificate and key files on filesystem
CERT="${1:-$CERT}"
KEY="${2:-$KEY}"
if [ -z "$CERT" ] || [ -z "$KEY" ]; then
  logger -p user.err -t traefik-cert "Error: Certificate and key file paths must be provided as arguments or environment variables."
  logger -t traefik-cert "Usage: $0 <path-to-cert> <path-to-key>"
  exit 1
fi
[ -f "$CERT" ] || { logger -p user.err -t traefik-cert "Certificate file not found: $CERT"; exit 1; }
[ -f "$KEY" ] || { logger -p user.err -t traefik-cert "Key file not found: $KEY"; exit 1; }


# Default namespace and secret name for Traefik TLS certs
NAMESPACE="traefik"
SECRET_NAME="traefik-cert"
BACKUP_SECRET=$(mktemp)


NEW_HASH=$(sha256sum "$CERT" | cut -d' ' -f1)
OLD_HASH=$(kubectl get secret "$SECRET_NAME" --ignore-not-found -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d | sha256sum | cut -d' ' -f1)
if [ "$NEW_HASH" == "$OLD_HASH" ]; then
  logger -t traefik-cert "No changes..."
  exit 0
fi

logger -t traefik-cert "Starting TLS secret update on secret $SECRET_NAME in namespace ${NAMESPACE}"

kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml \
  | grep -vE 'resourceVersion|uid|creationTimestamp' > "$BACKUP_SECRET" && \
logger -t traefik-cert "Backed up existing secret to $BACKUP_SECRET" && \
kubectl delete secret -n $NAMESPACE $SECRET_NAME --ignore-not-found && \
logger -t traefik-cert "Deleted existing secret" || \
logger -p user.warn -t traefik-cert "Failed to backup and delete existing secret. Trying to proceed with update..."

if kubectl create secret tls $SECRET_NAME \
  --cert=$CERT \
  --key=$KEY \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -; then
  logger -t traefik-cert "TLS secret updated successfully"
else
  logger -p user.err -t traefik-cert "TLS secret update FAILED"
  kubectl apply -f $BACKUP_SECRET
  logger -p user.warn -t traefik-cert "Restored previous secret version"
fi
