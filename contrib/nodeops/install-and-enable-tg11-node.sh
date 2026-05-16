#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE="seed"
NAME="${1:-}"
FQDN="${2:-}"
DATADIR=""
SERVICE_NAME=""
SERVICE_USER="tg11"
SERVICE_GROUP="tg11"
SETUP_FIREWALL=0
RPC_CIDR="127.0.0.1"
ADDNODES=()

usage() {
  cat <<'EOF'
Usage:
  install-and-enable-tg11-node.sh <name> <fqdn> [options]

Examples:
  install-and-enable-tg11-node.sh seed1 seed1.tg11.org --role seed --setup-firewall
  install-and-enable-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --rpc-cidr 10.10.0.0/16

Options:
  -r, --role <seed|full|private-rpc>
  -d, --datadir <path>           Default: /var/lib/tg11-<name>
  -s, --service-name <name>      Default: tg11d-<name>
  -a, --addnode <host:port>      Repeatable
      --service-user <user>      Default: tg11
      --service-group <group>    Default: tg11
      --setup-firewall           Apply UFW rules for role
      --rpc-cidr <cidr>          RPC allowlist CIDR for firewall helper
  -h, --help
EOF
}

if [[ -z "${NAME}" || -z "${FQDN}" ]]; then
  usage
  exit 1
fi

shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)
      ROLE="${2:-}"
      shift 2
      ;;
    -d|--datadir)
      DATADIR="${2:-}"
      shift 2
      ;;
    -s|--service-name)
      SERVICE_NAME="${2:-}"
      shift 2
      ;;
    -a|--addnode)
      ADDNODES+=("${2:-}")
      shift 2
      ;;
    --service-user)
      SERVICE_USER="${2:-}"
      shift 2
      ;;
    --service-group)
      SERVICE_GROUP="${2:-}"
      shift 2
      ;;
    --setup-firewall)
      SETUP_FIREWALL=1
      shift
      ;;
    --rpc-cidr)
      RPC_CIDR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${DATADIR}" ]]; then
  DATADIR="/var/lib/tg11-${NAME}"
fi

if [[ -z "${SERVICE_NAME}" ]]; then
  SERVICE_NAME="tg11d-${NAME}"
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required" >&2
  exit 1
fi

if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  sudo useradd --system --create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

if ! getent group "${SERVICE_GROUP}" >/dev/null 2>&1; then
  sudo groupadd --system "${SERVICE_GROUP}"
fi

sudo mkdir -p "${DATADIR}"
sudo chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${DATADIR}"

SETUP_CMD=(
  "${SCRIPT_DIR}/setup-tg11-node.sh"
  "${NAME}"
  "${FQDN}"
  --role "${ROLE}"
  --datadir "${DATADIR}"
  --service-name "${SERVICE_NAME}"
  --service-user "${SERVICE_USER}"
  --service-group "${SERVICE_GROUP}"
  --install-systemd
)

for node in "${ADDNODES[@]}"; do
  SETUP_CMD+=(--addnode "${node}")
done

"${SETUP_CMD[@]}"

if [[ "${SETUP_FIREWALL}" -eq 1 ]]; then
  "${SCRIPT_DIR}/firewall-ufw.sh" "${ROLE}" "${RPC_CIDR}"
fi

echo ""
echo "Install complete for ${NAME}."
echo "Service: ${SERVICE_NAME}.service"
echo "Datadir: ${DATADIR}"
echo "Check status: sudo systemctl status ${SERVICE_NAME}.service"
