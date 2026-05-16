#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
SERVICE_NAME="${2:-}"
BUILD_WALLET=0

usage() {
  cat <<'EOF'
Usage:
  update-tg11-node.sh <repo-root> <service-name> [--build-wallet]

Examples:
  update-tg11-node.sh /opt/tg11 tg11d-seed1.service
  update-tg11-node.sh /opt/tg11 tg11-rpc1.service --build-wallet
EOF
}

if [[ -z "${SERVICE_NAME}" ]]; then
  usage
  exit 1
fi

if [[ "${3:-}" == "--build-wallet" ]]; then
  BUILD_WALLET=1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required" >&2
  exit 1
fi

cd "${REPO_ROOT}"
git pull --ff-only

if [[ "${BUILD_WALLET}" -eq 1 ]]; then
  make -C src tg11d tg11-cli tg11-wallet -j"$(nproc)"
else
  make -C src tg11d tg11-cli -j"$(nproc)"
fi

sudo systemctl restart "${SERVICE_NAME}"
sudo systemctl --no-pager --full status "${SERVICE_NAME}" | head -n 30

echo "Update complete: ${SERVICE_NAME}"
