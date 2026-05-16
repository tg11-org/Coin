#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
RPC_CIDR="${2:-127.0.0.1}"

usage() {
  cat <<'EOF'
Usage: firewall-ufw.sh <seed|full|private-rpc> [rpc-cidr]

Examples:
  firewall-ufw.sh seed
  firewall-ufw.sh full
  firewall-ufw.sh private-rpc 10.10.0.0/16
EOF
}

if [[ -z "${ROLE}" ]]; then
  usage
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw is not installed. Install it first: sudo apt-get install -y ufw" >&2
  exit 1
fi

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH

case "${ROLE}" in
  seed|full)
    sudo ufw allow 31111/tcp
    # Optional: allow RPC only from trusted source(s)
    sudo ufw allow from "${RPC_CIDR}" to any port 31110 proto tcp
    ;;
  private-rpc)
    # No public P2P listener expected by default in private-rpc profile.
    sudo ufw allow from "${RPC_CIDR}" to any port 31110 proto tcp
    ;;
  *)
    echo "Unknown role: ${ROLE}" >&2
    usage
    exit 1
    ;;
esac

sudo ufw --force enable
sudo ufw status verbose
