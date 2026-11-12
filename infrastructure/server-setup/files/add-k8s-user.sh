#!/bin/bash
set -euo pipefail

# ====== CONFIG ======
K8S_CA_CERT="/etc/kubernetes/pki/ca.crt"
K8S_CA_KEY="/etc/kubernetes/pki/ca.key"
K8S_ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
OUTPUT_BASE="./user-kubeconfigs"
KUBE_API_HOST=${KUBE_API_HOST:-"localhost"}
KUBE_API_PORT=${KUBE_API_PORT:-"6443"}
ZIP_PASSWORD_PROMPT="Enter zip password (leave empty for no password): "
ASK_PASSWORD=${ASK_PASSWORD:-yes}
# Client certificates cannot be revoked, so keep them short-lived. Access is revoked by removing the ClusterRoleBinding
CERT_DAYS=${CERT_DAYS:-400}
# Requires: zip, openssl, kubectl
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (required for access to Kubernetes CA files)."
  exit 1
fi
# ====== USERNAME AND ROLE INPUT ======
# Usage: add-k8s-user.sh <username> [admin|operator]
#   admin    - cluster-admin
#   operator - read-only: no secrets, no exec/attach/port-forward, no RBAC (the default, least privilege)
USERNAME="${1:-}"
ROLE="${2:-operator}"
if [ -z "$USERNAME" ]; then
  read -rp "Enter username: " USERNAME
  [[ -z "$USERNAME" ]] && echo "Username cannot be empty!" && exit 1
fi
# The name ends up in a certificate subject, file paths and YAML
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_.-]{0,62}$ ]]; then
  echo "Invalid username: $USERNAME"
  exit 1
fi
if [[ "$ROLE" != "admin" && "$ROLE" != "operator" ]]; then
  echo "Invalid role: $ROLE (expected admin or operator)"
  exit 1
fi

USERDIR="${OUTPUT_BASE}/${USERNAME}"
mkdir -p "$USERDIR"

USER_KEY="${USERDIR}/${USERNAME}.key"
USER_CSR="${USERDIR}/${USERNAME}.csr"
USER_CERT="${USERDIR}/${USERNAME}.crt"
USER_KUBECONFIG="${USERDIR}/config"
ZIP_FILE="${OUTPUT_BASE}/${USERNAME}-config.zip"

# ====== KEY/CSR/CERT GEN ======
openssl genrsa -out "$USER_KEY" 2048
openssl req -new -key "$USER_KEY" -out "$USER_CSR" -subj "/CN=${USERNAME}"
openssl x509 -req -in "$USER_CSR" -CA "$K8S_CA_CERT" -CAkey "$K8S_CA_KEY" -CAcreateserial \
  -out "$USER_CERT" -days "$CERT_DAYS"

# ====== CLUSTER INFO (using ca.crt and YOUR public IP) ======
echo "Setting cluster server to https://${KUBE_API_HOST}:${KUBE_API_PORT}"
CLUSTER_NAME="public-k8s-$(hostname -s)"
CA_DATA=$(base64 -w0 "$K8S_CA_CERT")
CERT_DATA=$(base64 -w0 "$USER_CERT")
KEY_DATA=$(base64 -w0 "$USER_KEY")

cat > "$USER_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA}
    server: https://${KUBE_API_HOST}:${KUBE_API_PORT}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${USERNAME}
  name: ${USERNAME}@${CLUSTER_NAME}
current-context: ${USERNAME}@${CLUSTER_NAME}
users:
- name: ${USERNAME}
  user:
    client-certificate-data: ${CERT_DATA}
    client-key-data: ${KEY_DATA}
EOF

# ====== RBAC ======
BINDING_NAME="user-${ROLE}-${USERNAME}"
if [[ "$ROLE" == "admin" ]]; then
  ROLE_NAME="cluster-admin"
  OTHER_ROLE="operator"
else
  ROLE_NAME="opencrvs-operator"
  OTHER_ROLE="admin"
  # The role is created by the playbook (tasks/k8s/operator-role.yml)
  if ! kubectl --kubeconfig="$K8S_ADMIN_KUBECONFIG" get clusterrole "$ROLE_NAME" >/dev/null 2>&1; then
    echo "ClusterRole ${ROLE_NAME} does not exist. Run the playbook with the users tag first."
    exit 1
  fi
fi

cat <<EOF | kubectl --kubeconfig="$K8S_ADMIN_KUBECONFIG" apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${BINDING_NAME}
  labels:
    opencrvs.org/user: "${USERNAME}"
subjects:
- kind: User
  name: "${USERNAME}"
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: ${ROLE_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

# A user holds the binding of the current role only, so a demoted admin loses cluster-admin
kubectl --kubeconfig="$K8S_ADMIN_KUBECONFIG" delete clusterrolebinding "user-${OTHER_ROLE}-${USERNAME}" --ignore-not-found

# ====== ZIP ARCHIVE ======
echo
if [[ "${ASK_PASSWORD}" == "yes" ]]; then
  read -rsp "$ZIP_PASSWORD_PROMPT" ZIP_PASS
else
  ZIP_PASS=""
fi
echo
cd "$USERDIR"
if [[ -z "$ZIP_PASS" ]]; then
  zip -r "../${USERNAME}-config.zip" .
else
  zip -P "$ZIP_PASS" -r "../${USERNAME}-config.zip" kubeconfig "${USERNAME}.crt" "${USERNAME}.key"
fi
cd - > /dev/null

echo
echo "✅ User configuration has been packaged."
echo "ZIP archive: $ZIP_FILE"
echo "Distribute this file securely to the user."
echo
echo "How to extract:"
echo "  unzip ${USERNAME}-config.zip"
