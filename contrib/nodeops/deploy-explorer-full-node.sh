#!/bin/bash
set -e

# Deploy explorer + full node to 74.207.233.139
# Usage: bash deploy-explorer-full-node.sh <rpc_node_1> <rpc_node_2>
# Example: bash deploy-explorer-full-node.sh 173.230.135.139 173.230.135.143

RPC_NODE_1=${1:-"173.230.135.139"}
RPC_NODE_2=${2:-"173.230.135.143"}
EXTERNAL_IP="74.207.233.139"
INTERNAL_IP="172.31.111.10"
SERVICE_USER="tg11"

echo "=== Deploying Full Node + Explorer to $EXTERNAL_IP ==="

# 1. Install system dependencies
echo "[1/6] Installing system dependencies..."
apt-get update
apt-get install -y \
  build-essential libssl-dev libboost-all-dev \
  git curl wget \
  apache2 apache2-utils certbot python3-certbot-apache \
  nodejs npm \
  postgresql postgresql-contrib \
  supervisor

# 2. Create service user
echo "[2/6] Creating service user..."
useradd -m -s /bin/bash $SERVICE_USER || true

# 3. Download and install TG11 binary
echo "[3/6] Installing TG11 binary..."
mkdir -p /opt/tg11-bin
cd /opt/tg11-bin
# Download from release URL or use local path
if [ -f "/mnt/u/Projects/Crypto/release-artifacts/tg11-0.21.5.5-tg11-linux-x86_64.tar.gz" ]; then
  tar xzf /mnt/u/Projects/Crypto/release-artifacts/tg11-0.21.5.5-tg11-linux-x86_64.tar.gz
  cp tg11-0.21.5.5-tg11-linux-x86_64/bin/tg11d /usr/local/bin/tg11d
  chmod +x /usr/local/bin/tg11d
else
  echo "ERROR: Release archive not found. Please build TG11 first."
  exit 1
fi

# 4. Create full node data directory and systemd service
echo "[4/6] Setting up full node service..."
mkdir -p /var/lib/tg11-full1
chown -R $SERVICE_USER:$SERVICE_USER /var/lib/tg11-full1

cat > /etc/systemd/system/tg11d-full1.service << 'EOF'
[Unit]
Description=TG11 Full Node (full1)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tg11
ExecStart=/usr/local/bin/tg11d -datadir=/var/lib/tg11-full1 -listen -port=31111 -rpcport=31110 -rpcbind=127.0.0.1 -rpcallowip=127.0.0.1 -addnode=seed1.tg11.org:31111 -addnode=seed2.tg11.org:31111 -addnode=seed3.tg11.org:31111
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tg11d-full1
systemctl start tg11d-full1

echo "[*] Full node service started. Waiting for sync..."
sleep 5

# 5. Set up PostgreSQL for explorer indexer
echo "[5/6] Setting up PostgreSQL for explorer..."
sudo -u postgres psql << PSQL_EOF
CREATE USER explorer WITH PASSWORD 'explorer_testnet_pwd_change_me' CREATEDB;
CREATE DATABASE tg11_explorer OWNER explorer;
\c tg11_explorer
CREATE TABLE blocks (
  id SERIAL PRIMARY KEY,
  height BIGINT UNIQUE NOT NULL,
  hash TEXT UNIQUE NOT NULL,
  timestamp BIGINT NOT NULL,
  transactions INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE transactions (
  id SERIAL PRIMARY KEY,
  txid TEXT UNIQUE NOT NULL,
  block_height BIGINT,
  from_address TEXT,
  to_address TEXT,
  amount BIGINT,
  timestamp BIGINT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_txs_block ON transactions(block_height);
CREATE INDEX idx_txs_timestamp ON transactions(timestamp);
CREATE INDEX idx_txs_address ON transactions(from_address, to_address);
PSQL_EOF

# 6. Deploy explorer service (Node.js + Express)
echo "[6/6] Deploying explorer service..."
mkdir -p /opt/explorer
cat > /opt/explorer/server.js << 'EXPLORER_EOF'
const express = require('express');
const { Client } = require('pg');
const http = require('http');
const app = express();

const RPC_NODE = process.env.RPC_NODE || '173.230.135.139';
const RPC_PORT = 31110;
const DB_PASS = 'explorer_testnet_pwd_change_me';

const dbClient = new Client({
  user: 'explorer',
  password: DB_PASS,
  host: 'localhost',
  port: 5432,
  database: 'tg11_explorer'
});

app.use(express.static('public'));

// Simple RPC call helper
async function rpcCall(method, params = []) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: 1
    });

    const options = {
      hostname: RPC_NODE,
      port: RPC_PORT,
      path: '/',
      method: 'POST',
      auth: 'rpc:password',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': postData.length
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data).result);
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

// Routes
app.get('/api/height', async (req, res) => {
  try {
    const height = await rpcCall('getblockcount');
    res.json({ height });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/blocks', async (req, res) => {
  try {
    const rows = await dbClient.query('SELECT * FROM blocks ORDER BY height DESC LIMIT 10');
    res.json(rows.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/tx/:txid', async (req, res) => {
  try {
    const rows = await dbClient.query('SELECT * FROM transactions WHERE txid = $1', [req.params.txid]);
    res.json(rows.rows[0] || {});
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head><title>TG11 Explorer</title></head>
    <body>
      <h1>TG11 Testnet Explorer</h1>
      <div id="height"></div>
      <div id="blocks"></div>
      <script>
        fetch('/api/height').then(r => r.json()).then(d => {
          document.getElementById('height').innerHTML = 'Block Height: ' + d.height;
        });
        fetch('/api/blocks').then(r => r.json()).then(d => {
          document.getElementById('blocks').innerHTML = '<h2>Recent Blocks</h2><pre>' + JSON.stringify(d, null, 2) + '</pre>';
        });
      </script>
    </body>
    </html>
  `);
});

dbClient.connect().then(() => {
  app.listen(3000, () => console.log('Explorer listening on port 3000'));
});
EXPLORER_EOF

# Create package.json for explorer
cat > /opt/explorer/package.json << 'EOF'
{
  "name": "tg11-explorer",
  "version": "1.0.0",
  "description": "Block explorer for TG11 testnet",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0",
    "pg": "^8.8.0"
  }
}
EOF

cd /opt/explorer
npm install

# Create systemd service for explorer
cat > /etc/systemd/system/explorer.service << EOF
[Unit]
Description=TG11 Explorer Service
After=postgresql.service tg11d-full1.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/explorer
ExecStart=/usr/bin/node /opt/explorer/server.js
Environment="RPC_NODE=$RPC_NODE_1"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable explorer
systemctl start explorer

echo "=== Deployment Complete ==="
echo "Full Node: tg11d-full1 listening on port 31111"
echo "Full Node RPC: localhost:31110"
echo "Explorer Service: http://localhost:3000"
echo "Next: Configure Apache2 vhost for explorer.testnet.tg11.org"
