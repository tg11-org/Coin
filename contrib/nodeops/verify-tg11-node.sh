#!/usr/bin/env bash
set -euo pipefail

DATADIR="${1:-}"
SERVICE_NAME="${2:-}"
CLI_PATH="${3:-./src/tg11-cli}"

usage() {
  cat <<'EOF'
Usage:
  verify-tg11-node.sh <datadir> [service-name] [cli-path]

Examples:
  verify-tg11-node.sh /var/lib/tg11-seed1 tg11d-seed1.service /opt/tg11/src/tg11-cli
  verify-tg11-node.sh /srv/tg11-rpc1
EOF
}

if [[ "${DATADIR}" == "--help" || "${DATADIR}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -z "${DATADIR}" ]]; then
  usage
  exit 1
fi

if [[ ! -x "${CLI_PATH}" ]]; then
  echo "CLI not executable: ${CLI_PATH}" >&2
  exit 1
fi

echo "== TG11 node verification =="
echo "datadir: ${DATADIR}"

echo "-- blockchain info"
"${CLI_PATH}" -datadir="${DATADIR}" getblockchaininfo

echo "-- network info"
"${CLI_PATH}" -datadir="${DATADIR}" getnetworkinfo

echo "-- peer count"
"${CLI_PATH}" -datadir="${DATADIR}" getconnectioncount

if [[ -n "${SERVICE_NAME}" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    echo "-- service status (${SERVICE_NAME})"
    sudo systemctl --no-pager --full status "${SERVICE_NAME}" | head -n 25
  else
    echo "systemctl not available; skipping service check"
  fi
fi

echo "Verification complete."
