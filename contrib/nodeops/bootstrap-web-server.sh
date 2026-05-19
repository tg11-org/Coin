#!/usr/bin/env bash
set -euo pipefail

# One-shot bootstrap for public testnet web servers.
# Clones repo, builds TG11 from source, deploys services + SSL.
#
# Usage:
#   sudo bash bootstrap-web-server.sh explorer-full1 173.230.135.139 173.230.135.143 gage@tg11.org
#   sudo bash bootstrap-web-server.sh faucet-status 173.230.135.139 173.230.135.143 gage@tg11.org

ROLE="${1:-}"
RPC_NODE_1="${2:-173.230.135.139}"
RPC_NODE_2="${3:-173.230.135.143}"
CERT_EMAIL="${4:-admin@tg11.org}"
REPO_URL="${REPO_URL:-https://github.com/tg11-org/Coin.git}"
REPO_ROOT="/opt/tg11"

usage() {
  cat <<'EOF'
Usage:
  sudo bash bootstrap-web-server.sh <explorer-full1|faucet-status> [rpc_node_1] [rpc_node_2] [cert_email]

Examples:
  sudo bash bootstrap-web-server.sh explorer-full1 173.230.135.139 173.230.135.143 ops@tg11.org
  sudo bash bootstrap-web-server.sh faucet-status 173.230.135.139 173.230.135.143 ops@tg11.org
EOF
}

if [[ -z "${ROLE}" ]]; then
  usage
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

echo "=== Bootstrapping ${ROLE} web server ==="
echo "  Repo: ${REPO_URL}"
echo "  Root: ${REPO_ROOT}"
echo "  Role: ${ROLE}"
echo "  RPC1: ${RPC_NODE_1}"
echo "  RPC2: ${RPC_NODE_2}"
echo "  Email: ${CERT_EMAIL}"
echo ""

# 1. Clone or update repo
if [[ ! -d "${REPO_ROOT}/.git" ]]; then
  echo "[1/5] Cloning TG11 repository..."
  git clone "${REPO_URL}" "${REPO_ROOT}"
else
  echo "[1/5] Updating existing TG11 repository..."
  cd "${REPO_ROOT}"
  git pull --ff-only
fi

cd "${REPO_ROOT}"

# 2. Install system dependencies
echo "[2/5] Installing system dependencies and building TG11..."

# Clean up problematic repos that might cause update failures
echo "  Cleaning up problematic APT repositories..."
rm -f /etc/apt/sources.list.d/bitcoin*.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/longview*.list 2>/dev/null || true
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FA040280F4193789 2>/dev/null || true

# Update package list, allow some warnings
DEBIAN_FRONTEND=noninteractive apt-get update -y 2>&1 | grep -v "^W:" || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  build-essential autoconf automake libtool pkg-config \
  libevent-dev libboost-system-dev libboost-filesystem-dev \
  libboost-chrono-dev libboost-test-dev libboost-thread-dev \
  libsqlite3-dev libminiupnpc-dev libzmq3-dev libssl-dev \
  libfmt-dev libdb++-dev \
  git curl wget jq \
  apache2 apache2-utils certbot python3-certbot-apache \
  nodejs npm postgresql postgresql-contrib 2>&1 || {
    echo "  Install incomplete; retrying missing packages..."
    apt-get install -y --fix-missing 2>&1 | tail -5
  }

# Build TG11 from source
if [[ ! -f "${REPO_ROOT}/src/tg11d" ]]; then
  echo "  Building TG11d and tg11-cli..."
  chmod +x share/genbuild.sh 2>/dev/null || true
  bash autogen.sh 2>/dev/null || true
  ./configure --without-gui --disable-tests --disable-bench --disable-wallet >/dev/null 2>&1
  make -j2 >/dev/null 2>&1 || make -j1 >/dev/null 2>&1
  if [[ ! -f "${REPO_ROOT}/src/tg11d" ]]; then
    echo "Build failed. Check ${REPO_ROOT}/config.log"
    exit 1
  fi
fi

configure_ssl_inline() {
  local role="$1"
  local email="$2"

  a2enmod ssl rewrite headers proxy proxy_http >/dev/null 2>&1 || true

  if [[ "${role}" == "explorer-full1" ]]; then
    mkdir -p /var/www/tg11-full1
    cat > /var/www/tg11-full1/index.html <<'EOF'
<html><body><h1>TG11 Full1 Node</h1><p>full1.testnet.tg11.org is online.</p></body></html>
EOF

    cat > /etc/apache2/sites-available/tg11-testnet-explorer.conf <<'EOF'
<VirtualHost *:80>
  ServerName explorer.testnet.tg11.org
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:3000/
  ProxyPassReverse / http://127.0.0.1:3000/
  ErrorLog ${APACHE_LOG_DIR}/explorer-error.log
  CustomLog ${APACHE_LOG_DIR}/explorer-access.log combined
</VirtualHost>

<VirtualHost *:80>
  ServerName full1.testnet.tg11.org
  DocumentRoot /var/www/tg11-full1
  <Directory /var/www/tg11-full1>
    Require all granted
  </Directory>
  ErrorLog ${APACHE_LOG_DIR}/full1-error.log
  CustomLog ${APACHE_LOG_DIR}/full1-access.log combined
</VirtualHost>
EOF

    a2ensite tg11-testnet-explorer.conf >/dev/null 2>&1 || true
    systemctl reload apache2
    certbot --apache --non-interactive --agree-tos --email "${email}" --redirect \
      -d explorer.testnet.tg11.org -d full1.testnet.tg11.org
  else
    cat > /etc/apache2/sites-available/tg11-testnet-faucet-status.conf <<'EOF'
<VirtualHost *:80>
  ServerName faucet.testnet.tg11.org
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:3001/
  ProxyPassReverse / http://127.0.0.1:3001/
  ErrorLog ${APACHE_LOG_DIR}/faucet-error.log
  CustomLog ${APACHE_LOG_DIR}/faucet-access.log combined
</VirtualHost>

<VirtualHost *:80>
  ServerName status.testnet.tg11.org
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:3002/
  ProxyPassReverse / http://127.0.0.1:3002/
  ErrorLog ${APACHE_LOG_DIR}/status-error.log
  CustomLog ${APACHE_LOG_DIR}/status-access.log combined
</VirtualHost>
EOF

    a2ensite tg11-testnet-faucet-status.conf >/dev/null 2>&1 || true
    systemctl reload apache2
    certbot --apache --non-interactive --agree-tos --email "${email}" --redirect \
      -d faucet.testnet.tg11.org -d status.testnet.tg11.org
  fi

  systemctl reload apache2
}

# 3. Deploy service(s) based on role
echo "[3/5] Deploying ${ROLE} services..."
case "${ROLE}" in
  explorer-full1)
    sed -i 's/\r$//' contrib/nodeops/install-and-enable-tg11-node.sh 2>/dev/null || true
    chmod +x contrib/nodeops/install-and-enable-tg11-node.sh 2>/dev/null || true
    bash contrib/nodeops/install-and-enable-tg11-node.sh full1 full1.testnet.tg11.org \
      --role full --datadir /var/lib/tg11-full1 --service-name tg11d-full1 \
      --setup-firewall --rpc-cidr 127.0.0.1 \
      --addnode seed1.testnet.tg11.org:31111 \
      --addnode seed2.testnet.tg11.org:31111 \
      --addnode seed3.testnet.tg11.org:31111
    
    # Deploy explorer service
    mkdir -p /opt/explorer
    echo "  Deploying explorer service..."
    npm_set_registry() { npm config set registry https://registry.npmjs.org/ 2>/dev/null || true; }
    npm_set_registry
    cd /opt/explorer
    npm install express pg 2>/dev/null || true
    
    cat > /opt/explorer/server.js <<'EXPLORER_JS'
const express = require('express');
const { Client } = require('pg');
const http = require('http');
const app = express();
const RPC_NODE = '173.230.135.139';
const RPC_PORT = 31110;

const dbClient = new Client({
  user: 'explorer', password: 'explorer_testnet', host: 'localhost', port: 5432, database: 'tg11_explorer'
});

async function rpcCall(method, params = []) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 });
    const opts = { hostname: RPC_NODE, port: RPC_PORT, path: '/', method: 'POST', auth: 'rpc:password',
      headers: { 'Content-Type': 'application/json', 'Content-Length': postData.length } };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => { try { resolve(JSON.parse(data).result); } catch (e) { reject(e); } });
    });
    req.on('error', reject); req.write(postData); req.end();
  });
}

app.get('/api/height', async (req, res) => {
  try { const h = await rpcCall('getblockcount'); res.json({ height: h }); } catch (e) { res.status(500).json({ error: e.message }); }
});
app.get('/', (req, res) => { res.send('<h1>TG11 Explorer</h1><p>Explorer service running on port 3000</p>'); });

dbClient.connect().then(() => { app.listen(3000, () => console.log('Explorer on :3000')); }).catch(e => console.error('DB:', e));
EXPLORER_JS

    cat > /opt/explorer/package.json <<'EOF'
{ "name": "tg11-explorer", "version": "1.0.0", "dependencies": { "express": "^4.18.0", "pg": "^8.8.0" } }
EOF
    
    systemctl daemon-reload
    cat > /etc/systemd/system/explorer.service <<'EOF'
[Unit]
Description=TG11 Explorer Service
After=postgresql.service tg11d-full1.service
[Service]
Type=simple
User=root
WorkingDirectory=/opt/explorer
ExecStart=/usr/bin/node /opt/explorer/server.js
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable explorer 2>/dev/null
    systemctl start explorer 2>/dev/null || true
    ;;
    
  faucet-status)
    mkdir -p /opt/faucet /opt/status
    echo "  Deploying faucet service..."
    cd /opt/faucet
    npm install express sqlite3 2>/dev/null || true
    
    cat > /opt/faucet/faucet.js <<'FAUCET_JS'
const express = require('express');
const sqlite3 = require('sqlite3');
const http = require('http');
const app = express();
const RPC_NODE = '173.230.135.139';
const RPC_PORT = 31110;
const db = new sqlite3.Database('/opt/faucet/faucet.db');

db.run(`CREATE TABLE IF NOT EXISTS requests (
  id INTEGER PRIMARY KEY, ip_address TEXT NOT NULL, recipient_address TEXT NOT NULL,
  amount INTEGER NOT NULL, txid TEXT, timestamp INTEGER NOT NULL
)`);

app.use(express.json());
app.get('/', (req, res) => { res.send('<h1>TG11 Faucet</h1><p>Faucet service running on port 3001</p>'); });
app.listen(3001, () => console.log('Faucet on :3001'));
FAUCET_JS

    cat > /opt/faucet/package.json <<'EOF'
{ "name": "tg11-faucet", "version": "1.0.0", "dependencies": { "express": "^4.18.0", "sqlite3": "^5.1.0" } }
EOF
    
    echo "  Deploying status service..."
    cd /opt/status
    npm install express 2>/dev/null || true
    
    cat > /opt/status/status.js <<'STATUS_JS'
const express = require('express');
const http = require('http');
const app = express();

async function rpcCall(node, method) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({ jsonrpc: '2.0', method, params: [], id: 1 });
    const opts = { hostname: node, port: 31110, path: '/', method: 'POST', auth: 'rpc:password',
      headers: { 'Content-Type': 'application/json', 'Content-Length': postData.length } };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => { try { resolve(JSON.parse(data).result); } catch (e) { reject(e); } });
    });
    req.on('error', reject); req.write(postData); req.end();
  });
}

app.get('/', async (req, res) => {
  try {
    const h1 = await rpcCall('173.230.135.139', 'getblockcount');
    const h2 = await rpcCall('173.230.135.143', 'getblockcount');
    res.send(`<h1>TG11 Status</h1><pre>RPC1: ${h1}\nRPC2: ${h2}</pre>`);
  } catch (e) { res.send(`<h1>TG11 Status</h1><pre>Error: ${e.message}</pre>`); }
});
app.listen(3002, () => console.log('Status on :3002'));
STATUS_JS

    cat > /opt/status/package.json <<'EOF'
{ "name": "tg11-status", "version": "1.0.0", "dependencies": { "express": "^4.18.0" } }
EOF
    
    for svc in faucet status; do
      systemctl daemon-reload
      cat > /etc/systemd/system/${svc}.service <<EOF
[Unit]
Description=TG11 ${svc^} Service
After=network-online.target
[Service]
Type=simple
User=root
WorkingDirectory=/opt/${svc}
ExecStart=/usr/bin/node /opt/${svc}/${svc}.js
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable ${svc} 2>/dev/null
      systemctl start ${svc} 2>/dev/null || true
    done
    ;;
  *)
    echo "Unknown role: ${ROLE}"
    usage
    exit 1
    ;;
esac

# 4. Configure SSL
echo "[4/5] Configuring SSL certificates..."
configure_ssl_inline "${ROLE}" "${CERT_EMAIL}"

# 5. Verify
echo "[5/5] Verifying services..."
sleep 3

echo ""
echo "=== Bootstrap complete ==="
case "${ROLE}" in
  explorer-full1)
    echo "  curl -I https://explorer.testnet.tg11.org"
    echo "  curl -I https://full1.testnet.tg11.org"
    ;;
  faucet-status)
    echo "  curl -I https://faucet.testnet.tg11.org"
    echo "  curl -I https://status.testnet.tg11.org"
    ;;
esac
