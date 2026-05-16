#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROLE="seed"
NAME="${1:-}"
FQDN="${2:-}"
DATADIR=""
ADDNODES=()
INSTALL_SYSTEMD=0
ENABLE_SERVICE=1
START_SERVICE=1
SERVICE_NAME=""
SERVICE_USER="tg11"
SERVICE_GROUP="tg11"
WRITE_SERVICE_FILE=""

usage() {
  cat <<'EOF'
Usage:
  setup-tg11-node.sh <name> <fqdn> [options]

Examples:
  setup-tg11-node.sh seed1 seed1.tg11.org
  setup-tg11-node.sh seed2 seed2.tg11.org --role seed
  setup-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --datadir /srv/tg11-rpc1
  setup-tg11-node.sh full1 full1.tg11.org --role full --addnode seed1.tg11.org:31111
  setup-tg11-node.sh seed1 seed1.tg11.org --role seed --install-systemd
  setup-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --install-systemd --service-name tg11-rpc1

Options:
  -r, --role <seed|full|private-rpc>
  -d, --datadir <path>           Default: /var/lib/tg11-<name>
  -a, --addnode <host:port>      Repeatable
      --install-systemd          Install a per-node systemd unit in /etc/systemd/system
      --service-name <name>      Service name without .service (default: tg11d-<name>)
      --service-user <user>      Service user (default: tg11)
      --service-group <group>    Service group (default: tg11)
      --repo-root <path>         TG11 repo path for ExecStart/ExecStop (default: auto)
      --no-enable                Do not enable service on boot
      --no-start                 Do not start/restart service after install
      --write-service-file <p>   Write generated unit to a local file path
  -h, --help
EOF
}

generate_systemd_unit() {
  local unit_path="$1"
  local bin_dir="${REPO_ROOT}/src"

  cat > "${unit_path}" <<EOF
[Unit]
Description=TG11 daemon (${NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
ExecStart=${bin_dir}/tg11d -daemon -datadir=${DATADIR} -pid=${DATADIR}/tg11d.pid
ExecStop=${bin_dir}/tg11-cli -datadir=${DATADIR} stop
PIDFile=${DATADIR}/tg11d.pid
Restart=on-failure
RestartSec=5
TimeoutStartSec=180
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF
}

install_systemd_unit() {
  local local_unit_path="$1"
  local target_name="$2"
  local target_path="/etc/systemd/system/${target_name}.service"

  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required for --install-systemd" >&2
    exit 1
  fi

  sudo install -m 0644 "${local_unit_path}" "${target_path}"
  sudo systemctl daemon-reload
  if [[ "${ENABLE_SERVICE}" -eq 1 ]]; then
    sudo systemctl enable "${target_name}.service"
  fi
  if [[ "${START_SERVICE}" -eq 1 ]]; then
    sudo systemctl restart "${target_name}.service"
  fi
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
    -a|--addnode)
      ADDNODES+=("${2:-}")
      shift 2
      ;;
    --install-systemd)
      INSTALL_SYSTEMD=1
      shift
      ;;
    --service-name)
      SERVICE_NAME="${2:-}"
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
    --repo-root)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --no-enable)
      ENABLE_SERVICE=0
      shift
      ;;
    --no-start)
      START_SERVICE=0
      shift
      ;;
    --write-service-file)
      WRITE_SERVICE_FILE="${2:-}"
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

CMD=(
  "${SCRIPT_DIR}/bootstrap-tg11-node.sh"
  --role "${ROLE}"
  --name "${NAME}"
  --fqdn "${FQDN}"
  --datadir "${DATADIR}"
)

for node in "${ADDNODES[@]}"; do
  CMD+=(--addnode "${node}")
done

"${CMD[@]}"

TMP_UNIT_PATH="$(mktemp)"
trap 'rm -f "${TMP_UNIT_PATH}"' EXIT
generate_systemd_unit "${TMP_UNIT_PATH}"

if [[ -n "${WRITE_SERVICE_FILE}" ]]; then
  cp "${TMP_UNIT_PATH}" "${WRITE_SERVICE_FILE}"
  echo "Wrote generated systemd unit to ${WRITE_SERVICE_FILE}"
fi

if [[ "${INSTALL_SYSTEMD}" -eq 1 ]]; then
  install_systemd_unit "${TMP_UNIT_PATH}" "${SERVICE_NAME}"
fi

echo ""
echo "Node profile prepared for ${NAME} (${ROLE}) at ${DATADIR}"
echo "Config: ${DATADIR}/tg11.conf"
echo "Suggested service name: ${SERVICE_NAME}.service"
echo "Upgrade flow:"
echo "  git pull"
echo "  sudo systemctl restart ${SERVICE_NAME}.service"
