#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_ORCH="${SCRIPT_DIR}/fleet-orchestrate.sh"

INVENTORY=""
REPO_ROOT="/opt/tg11"
REPO_URL="https://github.com/TrentonGage11/Coin.git"
BRANCH=""
SSH_KEY=""
DRY_RUN=0
SKIP_PREPARE=0
SKIP_INSTALL=0
SKIP_VERIFY=0

usage() {
  cat <<'EOF'
Usage:
  fleet-bootstrap-all.sh --inventory <hosts.tsv> [options]

What it does by default:
1) Prepares/updates repo on all hosts over SSH
2) Runs fleet install/configure on all hosts
3) Runs fleet verify on all hosts

Options:
  --inventory <path>      TSV inventory file (required)
  --repo-root <path>      Remote repo path (default: /opt/tg11)
  --repo-url <url>        Git URL to clone when repo absent
  --branch <name>         Optional branch to checkout/pull
  --ssh-key <path>        SSH private key
  --dry-run               Print commands only
  --skip-prepare          Skip git clone/pull stage
  --skip-install          Skip install/config stage
  --skip-verify           Skip verify stage
  -h, --help

Example:
  contrib/nodeops/fleet-bootstrap-all.sh \
    --inventory contrib/nodeops/fleet/hosts.example.tsv \
    --repo-root /opt/tg11 \
    --repo-url https://github.com/TrentonGage11/Coin.git
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY="${2:-}"
      shift 2
      ;;
    --repo-root)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-prepare)
      SKIP_PREPARE=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --skip-verify)
      SKIP_VERIFY=1
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

if [[ -z "${INVENTORY}" ]]; then
  usage
  exit 1
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Inventory not found: ${INVENTORY}" >&2
  exit 1
fi

if [[ ! -x "${FLEET_ORCH}" ]]; then
  echo "Missing executable fleet orchestrator: ${FLEET_ORCH}" >&2
  echo "Try: chmod +x ${FLEET_ORCH}" >&2
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

prepare_remote_repos() {
  local line name role fqdn ssh_host ssh_user datadir service_name rpc_cidr target remote_cmd

  while IFS=$'\t' read -r name role fqdn ssh_host ssh_user datadir service_name rpc_cidr; do
    name="${name%$'\r'}"
    role="${role%$'\r'}"
    fqdn="${fqdn%$'\r'}"
    ssh_host="${ssh_host%$'\r'}"
    ssh_user="${ssh_user%$'\r'}"

    [[ -z "${name}" ]] && continue
    [[ "${name}" =~ ^# ]] && continue

    fqdn="${fqdn:-${name}}"
    ssh_host="${ssh_host:-${fqdn}}"
    ssh_user="${ssh_user:-root}"
    target="${ssh_user}@${ssh_host}"

    remote_cmd="set -euo pipefail; "
    remote_cmd+="if [[ -d '${REPO_ROOT}/.git' ]]; then "
    remote_cmd+="cd '${REPO_ROOT}'; git fetch --all --prune; "

    if [[ -n "${BRANCH}" ]]; then
      remote_cmd+="git checkout '${BRANCH}'; git pull --ff-only origin '${BRANCH}'; "
    else
      remote_cmd+="git pull --ff-only; "
    fi

    remote_cmd+="else "
    remote_cmd+="mkdir -p '$(dirname "${REPO_ROOT}")'; "
    remote_cmd+="git clone '${REPO_URL}' '${REPO_ROOT}'; "

    if [[ -n "${BRANCH}" ]]; then
      remote_cmd+="cd '${REPO_ROOT}'; git checkout '${BRANCH}'; "
    fi

    remote_cmd+="fi; "
    remote_cmd+="cd '${REPO_ROOT}'; chmod +x contrib/nodeops/*.sh || true"

    echo "== prepare: ${name} (${target}) =="
    run_remote "${target}" "${remote_cmd}"
  done < "${INVENTORY}"
}

call_orchestrator() {
  local action="$1"
  local cmd=("${FLEET_ORCH}" --action "${action}" --inventory "${INVENTORY}" --repo-root "${REPO_ROOT}")

  if [[ -n "${SSH_KEY}" ]]; then
    cmd+=(--ssh-key "${SSH_KEY}")
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    cmd+=(--dry-run)
  fi

  "${cmd[@]}"
}

if [[ "${SKIP_PREPARE}" -eq 0 ]]; then
  prepare_remote_repos
fi

if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  call_orchestrator install
fi

if [[ "${SKIP_VERIFY}" -eq 0 ]]; then
  call_orchestrator verify
fi

echo "Fleet bootstrap workflow complete."
