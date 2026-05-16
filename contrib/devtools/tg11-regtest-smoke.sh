#!/usr/bin/env bash
set -euo pipefail

# Reproducible regtest smoke flow for TG11 wallet and transaction validation.
DATADIR="${DATADIR:-/tmp/tg11-regtest-smoke}"
SRCDIR="${SRCDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src" && pwd)}"
WALLET="${WALLET:-smoke}"

cleanup() {
  if "${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" getblockchaininfo >/dev/null 2>&1; then
    "${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" stop >/dev/null || true
  fi
}
trap cleanup EXIT

rm -rf "${DATADIR}"
mkdir -p "${DATADIR}"

"${SRCDIR}/tg11d" -regtest -datadir="${DATADIR}" -daemon
"${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwait createwallet "${WALLET}" >/dev/null

mining_addr=$("${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" getnewaddress)
"${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" generatetoaddress 101 "${mining_addr}" >/dev/null

balance_before=$("${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" getbalance)
recipient_addr=$("${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" getnewaddress)
txid=$("${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" sendtoaddress "${recipient_addr}" 1.0)

"${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" generatetoaddress 1 "${mining_addr}" >/dev/null

confirmations=$("${SRCDIR}/tg11-cli" -regtest -datadir="${DATADIR}" -rpcwallet="${WALLET}" gettransaction "${txid}" | grep -m1 '"confirmations"' | tr -cd '0-9-')

printf 'wallet=%s\n' "${WALLET}"
printf 'datadir=%s\n' "${DATADIR}"
printf 'balance_after_101=%s\n' "${balance_before}"
printf 'txid=%s\n' "${txid}"
printf 'confirmations=%s\n' "${confirmations}"

if [[ "${confirmations}" -lt 1 ]]; then
  echo "smoke test failed: transaction not confirmed" >&2
  exit 1
fi

echo "smoke test passed"
