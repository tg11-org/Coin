#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY="${REPO_ROOT}/contrib/nodeops/fleet/hosts.tsv"
CERT_FILE="${REPO_ROOT}/contrib/nodeops/ssl/tg11.org.pem"
KEY_FILE="${REPO_ROOT}/contrib/nodeops/ssl/tg11.org.key"

usage() {
  cat <<'EOF'
Usage:
  deploy-apache-fleet.sh [--inventory <path>] [--cert <path>] [--key <path>]

Defaults:
  --inventory contrib/nodeops/fleet/hosts.tsv
  --cert      contrib/nodeops/ssl/tg11.org.pem
  --key       contrib/nodeops/ssl/tg11.org.key
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY="$2"
      shift 2
      ;;
    --cert)
      CERT_FILE="$2"
      shift 2
      ;;
    --key)
      KEY_FILE="$2"
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

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Inventory not found: ${INVENTORY}" >&2
  exit 1
fi

if [[ ! -f "${CERT_FILE}" ]]; then
  echo "Certificate not found: ${CERT_FILE}" >&2
  exit 1
fi

if [[ ! -f "${KEY_FILE}" ]]; then
  echo "Private key not found: ${KEY_FILE}" >&2
  exit 1
fi

while IFS=$'\t' read -r name role fqdn ssh_host ssh_user datadir service_name rpc_cidr; do
  if [[ -z "${name}" || "${name}" == \#* ]]; then
    continue
  fi

  echo "==> ${name} (${ssh_host})"

  scp -o BatchMode=yes "${CERT_FILE}" "${ssh_user}@${ssh_host}:/tmp/tg11.org.pem"
  scp -o BatchMode=yes "${KEY_FILE}" "${ssh_user}@${ssh_host}:/tmp/tg11.org.key"

  ssh -o BatchMode=yes "${ssh_user}@${ssh_host}" "bash -s" -- "${name}" "${fqdn}" <<'REMOTE'
set -euo pipefail

NAME="$1"
FQDN="$2"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2

a2enmod ssl headers rewrite >/dev/null
mkdir -p /etc/ssl/tg11
install -o root -g root -m 600 /tmp/tg11.org.key /etc/ssl/tg11/tg11.org.key
install -o root -g root -m 644 /tmp/tg11.org.pem /etc/ssl/tg11/tg11.org.pem

cat > /var/www/html/index.html <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>TG11 Node ${NAME}</title>
</head>
<body style="font-family: sans-serif; margin: 2rem;">
  <h1>TG11 Node: ${NAME}</h1>
  <p>Host: ${FQDN}</p>
  <p>Status: Apache online (HTTP/HTTPS)</p>
</body>
</html>
EOF

cat > /etc/apache2/sites-available/tg11.conf <<EOF
<VirtualHost *:80>
    ServerName ${FQDN}
    ServerAlias ${NAME}
    DocumentRoot /var/www/html
    Redirect / https://${FQDN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${FQDN}
    ServerAlias ${NAME}
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile /etc/ssl/tg11/tg11.org.pem
    SSLCertificateKeyFile /etc/ssl/tg11/tg11.org.key

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    <Directory /var/www/html>
        Require all granted
        AllowOverride None
    </Directory>
</VirtualHost>
EOF

a2dissite 000-default >/dev/null || true
a2ensite tg11 >/dev/null
systemctl enable apache2 >/dev/null
systemctl restart apache2

if command -v ufw >/dev/null 2>&1; then
  ufw allow 80/tcp >/dev/null || true
  ufw allow 443/tcp >/dev/null || true
fi

rm -f /tmp/tg11.org.pem /tmp/tg11.org.key
echo "apache configured on ${NAME}"
REMOTE

done < "${INVENTORY}"

echo "Apache+SSL deployment complete for all inventory hosts."
