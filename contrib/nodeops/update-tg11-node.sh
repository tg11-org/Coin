#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
SERVICE_NAME="${2:-}"
BUILD_WALLET=0
BUILD_JOBS="1"

usage() {
  cat <<'EOF'
Usage:
  update-tg11-node.sh <repo-root> <service-name> [options]

Examples:
  update-tg11-node.sh /opt/tg11 tg11d-seed1.service
  update-tg11-node.sh /opt/tg11 tg11-rpc1.service --build-wallet
  update-tg11-node.sh /opt/tg11 tg11d-seed1.service --build-jobs 2

Options:
  --build-wallet          Also build tg11-wallet
  --build-jobs <n>        Build parallelism (default: 1)
EOF
}

if [[ -z "${SERVICE_NAME}" ]]; then
  usage
  exit 1
fi

shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-wallet)
      BUILD_WALLET=1
      shift
      ;;
    --build-jobs)
      BUILD_JOBS="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required" >&2
  exit 1
fi

install_build_deps_if_supported() {
  if ! command -v apt-get >/dev/null 2>&1; then
    return
  fi

  local -a pkgs=(
    build-essential
    autoconf
    automake
    libtool
    pkg-config
    libevent-dev
    libboost-system-dev
    libboost-filesystem-dev
    libboost-chrono-dev
    libboost-test-dev
    libboost-thread-dev
    libsqlite3-dev
    libminiupnpc-dev
    libzmq3-dev
    libssl-dev
    libfmt-dev
    libdb++-dev
  )

  sudo env DEBIAN_FRONTEND=noninteractive apt-get update -y
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

cd "${REPO_ROOT}"
git pull --ff-only

install_build_deps_if_supported

chmod +x "${REPO_ROOT}/autogen.sh" "${REPO_ROOT}/share/genbuild.sh" 2>/dev/null || true
if [[ ! -f "${REPO_ROOT}/config.status" ]]; then
  bash "${REPO_ROOT}/autogen.sh"
  ./configure --without-gui --disable-tests --disable-bench --disable-wallet
fi

if [[ "${BUILD_WALLET}" -eq 1 ]]; then
  make -j"${BUILD_JOBS}" tg11d tg11-cli tg11-wallet
else
  make -j"${BUILD_JOBS}" tg11d tg11-cli
fi

sudo systemctl restart "${SERVICE_NAME}"
sudo systemctl --no-pager --full status "${SERVICE_NAME}" | head -n 30

echo "Update complete: ${SERVICE_NAME}"
