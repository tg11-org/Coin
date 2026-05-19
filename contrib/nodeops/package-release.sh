#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

VERSION="${VERSION:-}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/release-artifacts}"
DIST_NAME="${DIST_NAME:-tg11}"
BIN_DIR="${BIN_DIR:-${REPO_ROOT}/src}"

usage() {
  cat <<'EOF'
Usage:
  package-release.sh --version <version> [options]

Options:
  --version <version>      Required release version string
  --out-dir <path>         Output directory (default: ./release-artifacts)
  --dist-name <name>       Archive prefix (default: tg11)
  --bin-dir <path>         Directory containing tg11d/tg11-cli (default: ./src)
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --dist-name)
      DIST_NAME="${2:-}"
      shift 2
      ;;
    --bin-dir)
      BIN_DIR="${2:-}"
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

if [[ -z "${VERSION}" ]]; then
  echo "Missing required --version" >&2
  usage
  exit 1
fi

TG11D="${BIN_DIR}/tg11d"
TG11CLI="${BIN_DIR}/tg11-cli"

if [[ ! -x "${TG11D}" || ! -x "${TG11CLI}" ]]; then
  echo "Missing release binaries in ${BIN_DIR}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

PKG_DIR="${WORK_DIR}/${DIST_NAME}-${VERSION}"
mkdir -p "${PKG_DIR}/bin" "${PKG_DIR}/docs" "${PKG_DIR}/config"

cp "${TG11D}" "${PKG_DIR}/bin/"
cp "${TG11CLI}" "${PKG_DIR}/bin/"

for doc in README.md instructions.md docs/*.md; do
  if [[ -f "${WORKSPACE_ROOT}/${doc}" ]]; then
    mkdir -p "${PKG_DIR}/docs/$(dirname "${doc}")"
    cp "${WORKSPACE_ROOT}/${doc}" "${PKG_DIR}/docs/${doc}"
  fi
done

cp "${REPO_ROOT}/contrib/nodeops/tg11-mainnet-seed.conf" "${PKG_DIR}/config/"
cp "${REPO_ROOT}/contrib/nodeops/tg11-mainnet-full.conf" "${PKG_DIR}/config/"
cp "${REPO_ROOT}/contrib/nodeops/tg11-mainnet-private-rpc.conf" "${PKG_DIR}/config/"

cat > "${PKG_DIR}/RELEASE-METADATA.txt" <<EOF
TG11 Release Package
Version: ${VERSION}
Upstream tree: ${REPO_ROOT}
Build host: $(uname -a)
Build date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

ARCHIVE_PATH="${OUT_DIR}/${DIST_NAME}-${VERSION}-linux-x86_64.tar.gz"
tar -C "${WORK_DIR}" --owner=0 --group=0 --numeric-owner -czf "${ARCHIVE_PATH}" "${DIST_NAME}-${VERSION}"

(
  cd "${OUT_DIR}"
  sha256sum "$(basename "${ARCHIVE_PATH}")" > "SHA256SUMS-${VERSION}.txt"
)

echo "Created release archive: ${ARCHIVE_PATH}"
echo "Created checksum file: ${OUT_DIR}/SHA256SUMS-${VERSION}.txt"