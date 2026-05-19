#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROLE=""
DATADIR="/var/lib/tg11"
NODE_NAME=""
FQDN=""
RPC_USER=""
RPC_PASSWORD=""
FORCE=0
ADDNODES=()

usage() {
  cat <<'EOF'
Usage:
  bootstrap-tg11-node.sh --role <seed|full|private-rpc> [options]
  bootstrap-tg11-node.sh <seed|full|private-rpc> [datadir]

Examples:
  bootstrap-tg11-node.sh --role seed --name seed1 --fqdn seed1.tg11.org
  bootstrap-tg11-node.sh --role full --datadir /srv/tg11 --addnode seed1.tg11.org:31111
  bootstrap-tg11-node.sh --role private-rpc --rpcuser api --rpcpassword strong-pass

Options:
  -r, --role <role>            Node role: seed, full, private-rpc
  -d, --datadir <path>         Data directory (default: /var/lib/tg11)
  -n, --name <name>            Node name used in comments and uacomment
  -f, --fqdn <host>            Public host/IP used as externalip
  -a, --addnode <host:port>    Add bootstrap peer (repeatable)
      --rpcuser <user>         RPC username (recommended for private-rpc)
      --rpcpassword <pass>     RPC password (recommended for private-rpc)
      --force                  Overwrite existing litecoin.conf without backup prompt
  -h, --help                   Show this help
EOF
}

backup_and_copy_template() {
  local template="$1"
  local conf_path="$2"

  if [[ -f "${conf_path}" ]]; then
    if [[ "${FORCE}" -eq 0 ]]; then
      local ts
      ts="$(date +%Y%m%d-%H%M%S)"
      cp "${conf_path}" "${conf_path}.backup-${ts}"
      echo "Backed up existing config: ${conf_path}.backup-${ts}"
    fi
  fi

  cp "${template}" "${conf_path}"
}

append_value_if_set() {
  local key="$1"
  local value="$2"
  local conf_path="$3"
  if [[ -n "${value}" ]]; then
    echo "${key}=${value}" >> "${conf_path}"
  fi
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

parse_args() {
  if [[ $# -ge 1 ]] && [[ "${1}" != -* ]]; then
    ROLE="${1}"
    if [[ $# -ge 2 ]]; then
      DATADIR="${2}"
    fi
    return
  fi

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
      -n|--name)
        NODE_NAME="${2:-}"
        shift 2
        ;;
      -f|--fqdn)
        FQDN="${2:-}"
        shift 2
        ;;
      -a|--addnode)
        ADDNODES+=("${2:-}")
        shift 2
        ;;
      --rpcuser)
        RPC_USER="${2:-}"
        shift 2
        ;;
      --rpcpassword)
        RPC_PASSWORD="${2:-}"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
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
}

parse_args "$@"

if [[ -z "${ROLE}" ]]; then
  usage
  exit 1
fi

case "${ROLE}" in
  seed)
    TEMPLATE="${SCRIPT_DIR}/tg11-mainnet-seed.conf"
    ;;
  full)
    TEMPLATE="${SCRIPT_DIR}/tg11-mainnet-full.conf"
    ;;
  private-rpc)
    TEMPLATE="${SCRIPT_DIR}/tg11-mainnet-private-rpc.conf"
    ;;
  *)
    echo "Unknown role: ${ROLE}" >&2
    usage
    exit 1
    ;;
esac

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Template not found: ${TEMPLATE}" >&2
  exit 1
fi

mkdir -p "${DATADIR}"
CONF_PATH="${DATADIR}/litecoin.conf"

backup_and_copy_template "${TEMPLATE}" "${CONF_PATH}"

{
  echo ""
  echo "# Added by bootstrap-tg11-node.sh"
  append_value_if_set "uacomment" "${NODE_NAME}" "${CONF_PATH}"
  append_value_if_set "externalip" "${FQDN}" "${CONF_PATH}"
} >> "${CONF_PATH}"

if [[ "${#ADDNODES[@]}" -gt 0 ]]; then
  {
    echo "# Bootstrap peers"
    for node in "${ADDNODES[@]}"; do
      echo "addnode=${node}"
    done
  } >> "${CONF_PATH}"
fi

if [[ "${ROLE}" == "private-rpc" ]]; then
  if [[ -z "${RPC_USER}" ]]; then
    RPC_USER="tg11rpc"
  fi
  if [[ -z "${RPC_PASSWORD}" ]]; then
    RPC_PASSWORD="$(generate_password)"
  fi
  {
    echo "# RPC credentials"
    echo "rpcuser=${RPC_USER}"
    echo "rpcpassword=${RPC_PASSWORD}"
  } >> "${CONF_PATH}"
fi

# Service runs as tg11 user; keep config private but readable by service group.
chmod 640 "${CONF_PATH}" || true

echo "Wrote ${CONF_PATH} using role '${ROLE}'."
echo "Next steps:"
echo "  1. Review ${CONF_PATH} and verify networking/RPC settings"
echo "  2. Open firewall for P2P port 31111/TCP if this node accepts inbound"
echo "  3. Start node: src/tg11d -datadir=${DATADIR}"
