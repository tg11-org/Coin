#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

INVENTORY="${INVENTORY:-${SCRIPT_DIR}/fleet/public-testnet-hosts.example.tsv}"
REPO_URL="${REPO_URL:-https://github.com/tg11-org/Coin.git}"
REPO_ROOT_REMOTE="${REPO_ROOT_REMOTE:-/opt/tg11}"
DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat <<'EOF'
Usage:
  public-testnet-bootstrap.sh [--inventory <path>] [--repo-url <url>] [--repo-root <path>] [--dry-run]

Options:
  --inventory <path>     Fleet inventory TSV (default: contrib/nodeops/fleet/public-testnet-hosts.example.tsv)
  --repo-url <url>       Git clone URL for the TG11 repo
  --repo-root <path>     Remote repo path (default: /opt/tg11)
  --dry-run              Print actions without SSH changes
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --repo-root)
      REPO_ROOT_REMOTE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Inventory not found: ${INVENTORY}" >&2
  exit 1
fi

while IFS=$'\t' read -r name role fqdn ssh_host ssh_user datadir service_name rpc_cidr; do
  if [[ -z "${name}" || "${name}" == \#* ]]; then
    continue
  fi

  echo "==> ${name} (${role}) ${ssh_host}"
  echo "    repo: ${REPO_URL}"
  echo "    root: ${REPO_ROOT_REMOTE}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    continue
  fi

  case "${role}" in
    seed|full|private-rpc)
      ;;
    explorer|faucet|status|monitoring)
      echo "    skipping TG11 node bootstrap for service role '${role}'"
      continue
      ;;
    *)
      echo "Unknown role: ${role}" >&2
      exit 1
      ;;
  esac

  ssh -o BatchMode=yes "${ssh_user}@${ssh_host}" "bash -s" -- \
    "${name}" "${role}" "${fqdn}" "${REPO_URL}" "${REPO_ROOT_REMOTE}" "${datadir}" "${service_name}" "${rpc_cidr}" <<'REMOTE'
set -euo pipefail

NAME="$1"
ROLE="$2"
FQDN="$3"
REPO_URL="$4"
REPO_ROOT_REMOTE="$5"
DATADIR="$6"
SERVICE_NAME="$7"
RPC_CIDR="$8"

if [[ ! -d "${REPO_ROOT_REMOTE}/.git" ]]; then
  sudo mkdir -p "$(dirname "${REPO_ROOT_REMOTE}")"
  sudo git clone "${REPO_URL}" "${REPO_ROOT_REMOTE}"
else
  cd "${REPO_ROOT_REMOTE}"
  git pull --ff-only
fi

cd "${REPO_ROOT_REMOTE}"
case "${ROLE}" in
  seed)
    ./contrib/nodeops/install-and-enable-tg11-node.sh "${NAME}" "${FQDN}" --role seed --datadir "${DATADIR}" --service-name "${SERVICE_NAME}" --setup-firewall --rpc-cidr "${RPC_CIDR}"
    ;;
  private-rpc)
    ./contrib/nodeops/install-and-enable-tg11-node.sh "${NAME}" "${FQDN}" --role private-rpc --datadir "${DATADIR}" --service-name "${SERVICE_NAME}" --setup-firewall --rpc-cidr "${RPC_CIDR}"
    ;;
  full)
    ./contrib/nodeops/install-and-enable-tg11-node.sh "${NAME}" "${FQDN}" --role full --datadir "${DATADIR}" --service-name "${SERVICE_NAME}" --setup-firewall --rpc-cidr "${RPC_CIDR}"
    ;;
  *)
    echo "Unknown role: ${ROLE}" >&2
    exit 1
    ;;
esac
REMOTE
done < "${INVENTORY}"

echo "Public testnet bootstrap pass complete."