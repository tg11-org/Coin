#!/usr/bin/env bash
set -euo pipefail

ACTION=""
INVENTORY=""
REPO_ROOT="/opt/tg11"
SSH_KEY=""
DRY_RUN=0
BUILD_WALLET=0

usage() {
  cat <<'EOF'
Usage:
  fleet-orchestrate.sh --action <install|update|verify> --inventory <hosts.tsv> [options]

Options:
  --repo-root <path>     Remote TG11 repo root (default: /opt/tg11)
  --ssh-key <path>       SSH private key
  --build-wallet         For update action, also build tg11-wallet
  --dry-run              Print commands without executing
  -h, --help

Example:
  contrib/nodeops/fleet-orchestrate.sh --action install --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11
  contrib/nodeops/fleet-orchestrate.sh --action update --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    --inventory)
      INVENTORY="${2:-}"
      shift 2
      ;;
    --repo-root)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="${2:-}"
      shift 2
      ;;
    --build-wallet)
      BUILD_WALLET=1
      shift
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

if [[ -z "${ACTION}" || -z "${INVENTORY}" ]]; then
  usage
  exit 1
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Inventory not found: ${INVENTORY}" >&2
  exit 1
fi

case "${ACTION}" in
  install|update|verify)
    ;;
  *)
    echo "Invalid action: ${ACTION}" >&2
    usage
    exit 1
    ;;
esac

declare -a NAMES ROLES FQDNS HOSTS USERS DATADIRS SERVICES RPC_CIDRS SEEDS

while IFS=$'\t' read -r name role fqdn ssh_host ssh_user datadir service_name rpc_cidr; do
  name="${name%$'\r'}"
  role="${role%$'\r'}"
  fqdn="${fqdn%$'\r'}"
  ssh_host="${ssh_host%$'\r'}"
  ssh_user="${ssh_user%$'\r'}"
  datadir="${datadir%$'\r'}"
  service_name="${service_name%$'\r'}"
  rpc_cidr="${rpc_cidr%$'\r'}"

  [[ -z "${name}" ]] && continue
  [[ "${name}" =~ ^# ]] && continue

  role="${role:-seed}"
  fqdn="${fqdn:-${name}}"
  ssh_host="${ssh_host:-${fqdn}}"
  ssh_user="${ssh_user:-root}"
  datadir="${datadir:-/var/lib/tg11-${name}}"
  service_name="${service_name:-tg11d-${name}}"
  rpc_cidr="${rpc_cidr:-127.0.0.1}"

  NAMES+=("${name}")
  ROLES+=("${role}")
  FQDNS+=("${fqdn}")
  HOSTS+=("${ssh_host}")
  USERS+=("${ssh_user}")
  DATADIRS+=("${datadir}")
  SERVICES+=("${service_name}")
  RPC_CIDRS+=("${rpc_cidr}")

  if [[ "${role}" == "seed" ]]; then
    SEEDS+=("${fqdn}")
  fi
done < "${INVENTORY}"

if [[ "${#NAMES[@]}" -eq 0 ]]; then
  echo "No hosts found in inventory: ${INVENTORY}" >&2
  exit 1
fi

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
if [[ -n "${SSH_KEY}" ]]; then
  SSH_OPTS+=(-i "${SSH_KEY}")
fi

run_remote() {
  local target="$1"
  local cmd="$2"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ${target}: ${cmd}"
    return
  fi

  ssh "${SSH_OPTS[@]}" "${target}" "bash -lc $(printf '%q' "${cmd}")"
}

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  role="${ROLES[$i]}"
  fqdn="${FQDNS[$i]}"
  host="${HOSTS[$i]}"
  user="${USERS[$i]}"
  datadir="${DATADIRS[$i]}"
  service="${SERVICES[$i]}"
  rpc_cidr="${RPC_CIDRS[$i]}"

  target="${user}@${host}"

  addnode_flags=""
  for seed in "${SEEDS[@]}"; do
    if [[ "${role}" == "seed" && "${seed}" == "${fqdn}" ]]; then
      continue
    fi
    addnode_flags+=" --addnode ${seed}:31111"
  done

  case "${ACTION}" in
    install)
      remote_cmd="cd ${REPO_ROOT}; contrib/nodeops/install-and-enable-tg11-node.sh ${name} ${fqdn} --role ${role} --datadir ${datadir} --service-name ${service} --setup-firewall --rpc-cidr ${rpc_cidr}${addnode_flags}"
      ;;
    update)
      wallet_flag=""
      if [[ "${BUILD_WALLET}" -eq 1 ]]; then
        wallet_flag=" --build-wallet"
      fi
      remote_cmd="cd ${REPO_ROOT}; contrib/nodeops/update-tg11-node.sh ${REPO_ROOT} ${service}.service${wallet_flag}"
      ;;
    verify)
      remote_cmd="cd ${REPO_ROOT}; contrib/nodeops/verify-tg11-node.sh ${datadir} ${service}.service ${REPO_ROOT}/src/tg11-cli"
      ;;
  esac

  echo "== ${ACTION}: ${name} (${target}) =="
  run_remote "${target}" "${remote_cmd}"
done

echo "Fleet action complete: ${ACTION}"
