#!/usr/bin/env bash
# TG11 regtest smoke test (datadir-preserving variant)
# This script runs a regtest wallet/mining/tx/confirmation flow but preserves the datadir for debugging.
# Usage: ./tg11-regtest-smoke-noclean.sh [DATADIR]

set -euo pipefail

TG11D=./src/tg11d
TG11CLI=./src/tg11-cli
TG11WALLET=./src/tg11-wallet
DATADIR="${1:-/tmp/tg11-regtest-noclean}"

# Start fresh if datadir does not exist, but do NOT delete if it does
mkdir -p "$DATADIR"

# Start daemon
$TG11D -regtest -daemon -datadir="$DATADIR"
sleep 2

# Wait for RPC
for i in {1..20}; do
  if $TG11CLI -regtest -datadir="$DATADIR" getblockchaininfo >/dev/null 2>&1; then break; fi
  sleep 1
done

# Create wallet if not exists
if ! $TG11CLI -regtest -datadir="$DATADIR" getwalletinfo >/dev/null 2>&1; then
  $TG11CLI -regtest -datadir="$DATADIR" createwallet default
fi

ADDR=$($TG11CLI -regtest -datadir="$DATADIR" getnewaddress)
$TG11CLI -regtest -datadir="$DATADIR" generatetoaddress 101 "$ADDR"
BAL=$($TG11CLI -regtest -datadir="$DATADIR" getbalance)
echo "balance_after_101=$BAL"
ADDR2=$($TG11CLI -regtest -datadir="$DATADIR" getnewaddress)
TXID=$($TG11CLI -regtest -datadir="$DATADIR" sendtoaddress "$ADDR2" 1)
$TG11CLI -regtest -datadir="$DATADIR" generatetoaddress 1 "$ADDR"
CONF=$($TG11CLI -regtest -datadir="$DATADIR" gettransaction "$TXID" | grep confirmations | head -1)
echo "$CONF"

# Stop daemon
$TG11CLI -regtest -datadir="$DATADIR" stop
sleep 2

echo "smoke test (noclean) passed. datadir preserved at $DATADIR"
