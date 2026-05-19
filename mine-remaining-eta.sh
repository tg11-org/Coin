#!/usr/bin/env bash
set -euo pipefail

# Mines one block at a time and reports per-block timing + rolling ETA.
# Defaults are set for your current local setup.

CLI_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src/tg11-cli"
DATADIR_DEFAULT="/home/${USER}/tg11-local"
LOG_DEFAULT="/home/${USER}/tg11-local/mining-progress.log"

CLI="${CLI:-$CLI_DEFAULT}"
DATADIR="${DATADIR:-$DATADIR_DEFAULT}"
TARGET_HEIGHT="${TARGET_HEIGHT:-110}"
ADDRESS="${ADDRESS:-}"
LOG_FILE="${LOG_FILE:-$LOG_DEFAULT}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"

usage() {
  echo "Usage: $0 -a <address> [options]"
  echo ""
  echo "Required:"
  echo "  -a, --address <addr>        Mining address"
  echo ""
  echo "Options:"
  echo "  -d, --datadir <path>        Datadir (default: ${DATADIR_DEFAULT})"
  echo "  -c, --cli <path>            tg11-cli path (default: ${CLI_DEFAULT})"
  echo "  -t, --target-height <n>     Stop at this chain height (default: 110)"
  echo "  -l, --log-file <path>       Log file path (default: ${LOG_DEFAULT})"
  echo "  -s, --sleep <seconds>       Sleep after each block (default: 0)"
  echo "  -h, --help                  Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--address)
      ADDRESS="$2"; shift 2 ;;
    -d|--datadir)
      DATADIR="$2"; shift 2 ;;
    -c|--cli)
      CLI="$2"; shift 2 ;;
    -t|--target-height)
      TARGET_HEIGHT="$2"; shift 2 ;;
    -l|--log-file)
      LOG_FILE="$2"; shift 2 ;;
    -s|--sleep)
      SLEEP_BETWEEN="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$ADDRESS" ]]; then
  echo "Error: address is required." >&2
  usage
  exit 1
fi

if [[ ! -x "$CLI" ]]; then
  echo "Error: tg11-cli not executable at: $CLI" >&2
  exit 1
fi

if [[ ! -d "$DATADIR" ]]; then
  echo "Error: datadir not found: $DATADIR" >&2
  exit 1
fi

if ! [[ "$TARGET_HEIGHT" =~ ^[0-9]+$ ]]; then
  echo "Error: target height must be an integer." >&2
  exit 1
fi

if ! [[ "$SLEEP_BETWEEN" =~ ^[0-9]+$ ]]; then
  echo "Error: sleep value must be an integer." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

run_cli() {
  "$CLI" -datadir="$DATADIR" "$@"
}

format_seconds() {
  local total="$1"
  local h m s
  h=$((total / 3600))
  m=$(((total % 3600) / 60))
  s=$((total % 60))
  printf "%02dh:%02dm:%02ds" "$h" "$m" "$s"
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

if ! run_cli getblockcount >/dev/null 2>&1; then
  echo "Error: cannot reach local RPC with current cli/datadir." >&2
  exit 1
fi

if ! run_cli validateaddress "$ADDRESS" | grep -q '"isvalid": true'; then
  echo "Error: address is not valid for this chain: $ADDRESS" >&2
  exit 1
fi

current_height="$(run_cli getblockcount)"
start_height="$current_height"

if (( current_height >= TARGET_HEIGHT )); then
  echo "Current height (${current_height}) is already at or above target (${TARGET_HEIGHT})."
  exit 0
fi

echo "============================================================" | tee -a "$LOG_FILE"
echo "Mining session started: $(timestamp)" | tee -a "$LOG_FILE"
echo "CLI: $CLI" | tee -a "$LOG_FILE"
echo "Datadir: $DATADIR" | tee -a "$LOG_FILE"
echo "Address: $ADDRESS" | tee -a "$LOG_FILE"
echo "Start height: $start_height" | tee -a "$LOG_FILE"
echo "Target height: $TARGET_HEIGHT" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"

session_start_epoch="$(date +%s)"
prev_block_epoch="$session_start_epoch"

while :; do
  current_height="$(run_cli getblockcount)"

  if (( current_height >= TARGET_HEIGHT )); then
    break
  fi

  remaining_before=$((TARGET_HEIGHT - current_height))
  block_start_epoch="$(date +%s)"

  mine_output="$(run_cli generatetoaddress 1 "$ADDRESS")"

  new_height="$(run_cli getblockcount)"
  block_end_epoch="$(date +%s)"
  block_seconds=$((block_end_epoch - block_start_epoch))

  if (( new_height <= current_height )); then
    echo "[$(timestamp)] WARNING: height did not increase (still ${new_height})." | tee -a "$LOG_FILE"
    if (( SLEEP_BETWEEN > 0 )); then sleep "$SLEEP_BETWEEN"; fi
    continue
  fi

  mined_in_session=$((new_height - start_height))
  total_elapsed=$((block_end_epoch - session_start_epoch))

  if (( mined_in_session > 0 )); then
    avg_seconds=$((total_elapsed / mined_in_session))
  else
    avg_seconds=0
  fi

  remaining_after=$((TARGET_HEIGHT - new_height))
  eta_seconds=$((remaining_after * avg_seconds))
  eta_wall_epoch=$((block_end_epoch + eta_seconds))
  eta_wall="$(date -d "@${eta_wall_epoch}" '+%Y-%m-%d %H:%M:%S')"

  line="[$(timestamp)] height ${current_height} -> ${new_height} | block_time=$(format_seconds "$block_seconds") | avg=$(format_seconds "$avg_seconds") | remaining=${remaining_after} | eta_in=$(format_seconds "$eta_seconds") | eta_at=${eta_wall}"
  echo "$line" | tee -a "$LOG_FILE"
  echo "[$(timestamp)] mined_hashes: ${mine_output}" >> "$LOG_FILE"

  prev_block_epoch="$block_end_epoch"

  if (( SLEEP_BETWEEN > 0 )); then
    sleep "$SLEEP_BETWEEN"
  fi
done

final_height="$(run_cli getblockcount)"
final_epoch="$(date +%s)"
final_elapsed=$((final_epoch - session_start_epoch))
final_mined=$((final_height - start_height))

if (( final_mined > 0 )); then
  final_avg=$((final_elapsed / final_mined))
else
  final_avg=0
fi

echo "============================================================" | tee -a "$LOG_FILE"
echo "Mining session finished: $(timestamp)" | tee -a "$LOG_FILE"
echo "Final height: ${final_height}" | tee -a "$LOG_FILE"
echo "Blocks mined this session: ${final_mined}" | tee -a "$LOG_FILE"
echo "Total elapsed: $(format_seconds "$final_elapsed")" | tee -a "$LOG_FILE"
echo "Average per block: $(format_seconds "$final_avg")" | tee -a "$LOG_FILE"
echo "Log file: ${LOG_FILE}" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"
