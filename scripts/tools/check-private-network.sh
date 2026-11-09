#!/usr/bin/env bash
# Checks that the environment is not reachable from the public internet.
# Run it from a host outside of the environment network, for example a GitHub-hosted runner.
#
# Usage: check-private-network.sh [DOMAIN [KUBE_MASTER_NODE [KUBE_API_HOST]]]
# An empty argument falls back to the environment variable of the same name, a host that stays empty is skipped.
# Every host is checked on TCP ports: DOMAIN on web and SSH ports, the Kubernetes hosts also on the cluster ports.
# PRIVATE_NETWORK_REQUIRED=false skips the check. ENVIRONMENT is used in messages.
#
# stdout is a Markdown summary (redirect it to $GITHUB_STEP_SUMMARY), stderr is the log.
# Exits with 1 when a host accepts connections on a checked port.
# ICMP is not checked: GitHub-hosted runners (Azure) cannot send ping to the public internet.
set -uo pipefail

log() { echo "$@" >&2; }

if [[ "${PRIVATE_NETWORK_REQUIRED:-}" == "false" ]]; then
  log "::warning::Private network check is skipped because PRIVATE_NETWORK_REQUIRED is set to 'false'."
  echo "## Private network check"
  echo
  echo "⚠️ Skipped because \`PRIVATE_NETWORK_REQUIRED\` is set to \`false\`. The environment may be exposed to the public internet."
  exit 0
fi

# Succeeds when a TCP connection to host $1, port $2 opens within 3 seconds (macOS has no timeout command)
tcp_open() {
  local pid watcher status
  { (exec 3<> "/dev/tcp/$1/$2") 2> /dev/null; } &
  pid=$!
  { sleep 3; kill "$pid"; } > /dev/null 2>&1 &
  watcher=$!
  { wait "$pid"; } 2> /dev/null
  status=$?
  { kill "$watcher"; wait "$watcher"; } > /dev/null 2>&1
  return "$status"
}

# Prints the IP addresses of host $1, nothing when it does not resolve (macOS has no getent)
resolve() {
  if command -v getent > /dev/null; then
    getent ahosts "$1" | awk '{print $1}' | sort -u
  else
    dscacheutil -q host -a name "$1" | awk '/ip(v6)?_address/ {print $2}' | sort -u
  fi
}

DOMAIN="${1:-${DOMAIN:-}}"
KUBE_MASTER_NODE="${2:-${KUBE_MASTER_NODE:-}}"
KUBE_API_HOST="${3:-${KUBE_API_HOST:-}}"
# TCP ports to check for the host of every variable
DOMAIN_PORTS=(22 80 443)
# SSH, HTTP, HTTPS, Kubernetes API, etcd client and peer, kubelet, controller manager, scheduler, Calico BGP, Calico Typha
KUBE_PORTS=(22 80 443 6443 2379 2380 10250 10257 10259 179 5473)
KUBE_MASTER_NODE_PORTS=("${KUBE_PORTS[@]}")
KUBE_API_HOST_PORTS=("${KUBE_PORTS[@]}")

exposed=0
rows=""
for name in DOMAIN KUBE_MASTER_NODE KUBE_API_HOST; do
  host="${!name}"
  [[ -z "$host" ]] && continue
  [[ "$host" =~ ^[A-Za-z0-9.:-]+$ ]] || { log "::error::Unexpected characters in $name: '$host'"; exit 1; }
  log "Checking $name $host from the public internet"
  address=$(resolve "$host" 2> /dev/null | paste -sd ',' - | sed 's/,/<br>/g')
  [[ -z "$address" ]] && address="⚠️ not resolved"

  ports=""
  ports_ref="${name}_PORTS[@]"
  for port in "${!ports_ref}"; do
    if tcp_open "$host" "$port"; then
      log "::error::$host accepts connections on port $port from the public internet"
      ports="$ports<br>$port ❌ open"
      exposed=1
    else
      ports="$ports<br>$port ✅ closed"
    fi
  done
  rows="$rows| \`$name\` | \`$host\` | $address | ${ports#<br>} |"$'\n'
done

if [[ -z "$rows" ]]; then
  log "::error::Nothing to check: DOMAIN, KUBE_MASTER_NODE and KUBE_API_HOST are all empty"
  exit 1
fi

[[ "$exposed" -eq 0 ]] && result="✅ The environment is not reachable from the public internet." || result="❌ The environment is reachable from the public internet."
printf '## Private network check\n\n%s\n\n| Variable | Host | Address | Port check |\n|----------|------|---------|------------|\n%s' "$result" "$rows"

log "$result"
if [[ "$exposed" -ne 0 ]]; then
  log "Deploy OpenCRVS to a private network (VPN, private subnet or firewall that only allows trusted addresses)."
  log "If your country intentionally exposes the environment, set the PRIVATE_NETWORK_REQUIRED variable of the '${ENVIRONMENT:-<environment>}' GitHub environment to 'false'."
  exit 1
fi
