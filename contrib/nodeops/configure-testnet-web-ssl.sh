#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
EMAIL="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  configure-testnet-web-ssl.sh <explorer-full1|faucet-status> <email>

Examples:
  sudo bash contrib/nodeops/configure-testnet-web-ssl.sh explorer-full1 ops@tg11.org
  sudo bash contrib/nodeops/configure-testnet-web-ssl.sh faucet-status ops@tg11.org

Notes:
  - Keep Cloudflare proxy OFF (DNS only) until cert issuance succeeds.
  - Script installs certbot + apache plugin and applies HTTPS redirects.
EOF
}

if [[ -z "${ROLE}" || -z "${EMAIL}" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

apt-get update
apt-get install -y apache2 certbot python3-certbot-apache

a2enmod ssl rewrite headers proxy proxy_http

case "${ROLE}" in
  explorer-full1)
    cp "${SCRIPT_DIR}/apache-vhost-explorer-server.conf" /etc/apache2/sites-available/testnet-explorer-full1.conf
    a2ensite testnet-explorer-full1.conf
    a2dissite 000-default || true
    systemctl reload apache2

    # Ensure placeholder page exists for full1 hostname.
    mkdir -p /var/www/full1-status
    cat > /var/www/full1-status/index.html <<'EOF'
<!doctype html>
<html>
<head><title>full1.testnet.tg11.org</title></head>
<body>
  <h1>full1.testnet.tg11.org</h1>
  <p>Full node host is online.</p>
</body>
</html>
EOF

    certbot --apache --non-interactive --agree-tos --redirect \
      -m "${EMAIL}" \
      -d explorer.testnet.tg11.org \
      -d full1.testnet.tg11.org
    ;;
  faucet-status)
    cp "${SCRIPT_DIR}/apache-vhost-faucet-status-server.conf" /etc/apache2/sites-available/testnet-faucet-status.conf
    a2ensite testnet-faucet-status.conf
    a2dissite 000-default || true
    systemctl reload apache2

    certbot --apache --non-interactive --agree-tos --redirect \
      -m "${EMAIL}" \
      -d faucet.testnet.tg11.org \
      -d status.testnet.tg11.org
    ;;
  *)
    echo "Unknown role: ${ROLE}"
    usage
    exit 1
    ;;
esac

systemctl reload apache2

echo "SSL configuration complete for role '${ROLE}'."
certbot certificates
