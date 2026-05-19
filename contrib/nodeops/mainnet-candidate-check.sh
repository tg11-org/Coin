#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "=== TG11 Mainnet Candidate Check ==="

REQUIRED_FILES=(
  "docs/ROADMAP.md"
  "docs/MAINNET_CANDIDATE.md"
  "docs/PACKAGING.md"
  "docs/PUBLIC_TESTNET.md"
  "docs/DEPLOYMENT.md"
  "docs/SEED_NODES.md"
  "docs/NETWORK_PARAMS.md"
)

missing=0
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${WORKSPACE_ROOT}/${file}" ]]; then
    echo "MISSING: ${file}"
    missing=1
  else
    echo "OK: ${file}"
  fi
done

echo ""
echo "Freeze checklist items:"
for item in \
  "network ports" \
  "address and key prefixes" \
  "BIP32 version bytes" \
  "genesis data" \
  "seed node list" \
  "explorer endpoints" \
  "release version naming"; do
  echo "- ${item}"
done

echo ""
if [[ "${missing}" -ne 0 ]]; then
  echo "Mainnet candidate check failed: one or more required docs are missing." >&2
  exit 1
fi

echo "Mainnet candidate check passed: documentation anchors are present."