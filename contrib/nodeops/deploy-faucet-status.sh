#!/bin/bash
set -e

# Deploy faucet + status page to 198.74.54.235

EXTERNAL_IP="198.74.54.235"
INTERNAL_IP="172.31.111.20"
RPC_NODE_1=${1:-"173.230.135.139"}
RPC_NODE_2=${2:-"173.230.135.143"}

echo "=== Deploying Faucet + Status Page to $EXTERNAL_IP ==="

# 1. Install system dependencies
echo "[1/4] Installing system dependencies..."
apt-get update
apt-get install -y \
  build-essential libssl-dev \
  git curl wget \
  apache2 apache2-utils certbot python3-certbot-apache \
  nodejs npm \
  sqlite3

# 2. Deploy faucet service
echo "[2/4] Deploying faucet service..."
mkdir -p /opt/faucet
cat > /opt/faucet/faucet.js << 'FAUCET_EOF'
const express = require('express');
const sqlite3 = require('sqlite3');
const http = require('http');
const app = express();

const RPC_NODE = process.env.RPC_NODE || '173.230.135.139';
const RPC_PORT = 31110;
const FAUCET_ADDRESS = 'VNgpS9ZrTHt2JbwVGoVncsBRuLNj25T7v2'; // Mining address from setup
const DISPENSE_AMOUNT = 1000000; // 0.01 TG11 in satoshis
const RATE_LIMIT_SECONDS = 3600; // 1 hour between requests per IP

const db = new sqlite3.Database('/opt/faucet/faucet.db');

// Initialize DB
db.run(`
  CREATE TABLE IF NOT EXISTS requests (
    id INTEGER PRIMARY KEY,
    ip_address TEXT NOT NULL,
    recipient_address TEXT NOT NULL,
    amount INTEGER NOT NULL,
    txid TEXT,
    timestamp INTEGER NOT NULL,
    UNIQUE(ip_address, timestamp)
  )
`);

app.use(express.json());
app.use(express.static('public'));

// Helper to make RPC calls
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
          const parsed = JSON.parse(data);
          if (parsed.error) reject(new Error(parsed.error.message));
          else resolve(parsed.result);
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

// Faucet endpoint
app.post('/api/request', async (req, res) => {
  const { address } = req.body;
  const ip = req.ip;

  // Validate address format (basic check)
  if (!address || address.length < 20) {
    return res.status(400).json({ error: 'Invalid address' });
  }

  // Check rate limit
  db.get(
    'SELECT timestamp FROM requests WHERE ip_address = ? ORDER BY timestamp DESC LIMIT 1',
    [ip],
    async (err, row) => {
      if (err) return res.status(500).json({ error: err.message });

      if (row) {
        const secondsSinceLastRequest = Math.floor(Date.now() / 1000) - row.timestamp;
        if (secondsSinceLastRequest < RATE_LIMIT_SECONDS) {
          const waitSeconds = RATE_LIMIT_SECONDS - secondsSinceLastRequest;
          return res.status(429).json({ 
            error: `Rate limited. Please wait ${waitSeconds} seconds before requesting again.` 
          });
        }
      }

      try {
        // Send coins to address
        // NOTE: This assumes faucet has sufficient balance and RPC auth is set up
        const txid = await rpcCall('sendtoaddress', [address, DISPENSE_AMOUNT / 1e8]);

        // Record in DB
        db.run(
          'INSERT INTO requests (ip_address, recipient_address, amount, txid, timestamp) VALUES (?, ?, ?, ?, ?)',
          [ip, address, DISPENSE_AMOUNT, txid, Math.floor(Date.now() / 1000)],
          (err) => {
            if (err) console.error('DB error:', err);
          }
        );

        res.json({ success: true, txid, amount: DISPENSE_AMOUNT / 1e8 });
      } catch (e) {
        res.status(500).json({ error: 'Faucet error: ' + e.message });
      }
    }
  );
});

app.get('/api/stats', (req, res) => {
  db.get(
    'SELECT COUNT(*) as total_requests, SUM(amount) as total_dispensed FROM requests',
    (err, row) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json(row || { total_requests: 0, total_dispensed: 0 });
    }
  );
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>TG11 Testnet Faucet</title>
      <style>
        body { font-family: Arial; max-width: 600px; margin: 50px auto; }
        input { width: 100%; padding: 10px; margin: 10px 0; }
        button { background: #0066cc; color: white; padding: 10px 20px; border: none; cursor: pointer; }
        #result { margin-top: 20px; padding: 10px; background: #f0f0f0; }
      </style>
    </head>
    <body>
      <h1>TG11 Testnet Faucet</h1>
      <p>Request test coins for the TG11 testnet.</p>
      <input type="text" id="address" placeholder="Enter your VNg... address" />
      <button onclick="requestCoins()">Request Coins</button>
      <div id="result"></div>
      <script>
        async function requestCoins() {
          const address = document.getElementById('address').value;
          const result = await fetch('/api/request', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ address })
          }).then(r => r.json());
          
          const resultDiv = document.getElementById('result');
          if (result.success) {
            resultDiv.innerHTML = 'Success! TXID: <code>' + result.txid + '</code><br>Amount: ' + result.amount + ' TG11';
          } else {
            resultDiv.innerHTML = 'Error: ' + result.error;
          }
        }
      </script>
    </body>
    </html>
  `);
});

app.listen(3001, () => console.log('Faucet listening on port 3001'));
FAUCET_EOF

# Create faucet package.json
cat > /opt/faucet/package.json << 'EOF'
{
  "name": "tg11-faucet",
  "version": "1.0.0",
  "description": "Test coin faucet for TG11 testnet",
  "main": "faucet.js",
  "dependencies": {
    "express": "^4.18.0",
    "sqlite3": "^5.1.0"
  }
}
EOF

cd /opt/faucet
npm install

# Create systemd service for faucet
cat > /etc/systemd/system/faucet.service << EOF
[Unit]
Description=TG11 Faucet Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/faucet
ExecStart=/usr/bin/node /opt/faucet/faucet.js
Environment="RPC_NODE=$RPC_NODE_1"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable faucet
systemctl start faucet

# 3. Deploy status page
echo "[3/4] Deploying status page..."
mkdir -p /opt/status
cat > /opt/status/status.js << 'STATUS_EOF'
const express = require('express');
const http = require('http');
const app = express();

const RPC_NODES = [
  process.env.RPC_NODE_1 || '173.230.135.139',
  process.env.RPC_NODE_2 || '173.230.135.143'
];
const RPC_PORT = 31110;

async function rpcCall(node, method, params = []) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: 1
    });

    const options = {
      hostname: node,
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
          const parsed = JSON.parse(data);
          if (parsed.error) reject(new Error(parsed.error.message));
          else resolve(parsed.result);
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

app.use(express.static('public'));

app.get('/api/status', async (req, res) => {
  try {
    const status = {
      nodes: {},
      timestamp: new Date().toISOString()
    };

    for (const node of RPC_NODES) {
      try {
        const height = await rpcCall(node, 'getblockcount');
        const bestBlockHash = await rpcCall(node, 'getbestblockhash');
        const peerInfo = await rpcCall(node, 'getpeerinfo');
        const mempool = await rpcCall(node, 'getmempoolinfo');

        status.nodes[node] = {
          height,
          bestBlockHash,
          peers: peerInfo.length,
          mempoolSize: mempool.size,
          status: 'OK'
        };
      } catch (e) {
        status.nodes[node] = { status: 'ERROR', message: e.message };
      }
    }

    res.json(status);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>TG11 Testnet Status</title>
      <style>
        body { font-family: Arial; max-width: 800px; margin: 20px auto; }
        .node { border: 1px solid #ccc; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .ok { border-left: 5px solid green; }
        .error { border-left: 5px solid red; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 8px; border: 1px solid #eee; }
      </style>
    </head>
    <body>
      <h1>TG11 Testnet Status</h1>
      <div id="status"></div>
      <script>
        async function updateStatus() {
          const response = await fetch('/api/status');
          const status = await response.json();
          
          let html = '<p>Last update: ' + status.timestamp + '</p>';
          for (const [node, info] of Object.entries(status.nodes)) {
            html += '<div class="node ' + (info.status === 'OK' ? 'ok' : 'error') + '">';
            html += '<h3>' + node + '</h3>';
            if (info.status === 'OK') {
              html += '<table>';
              html += '<tr><td>Height</td><td>' + info.height + '</td></tr>';
              html += '<tr><td>Hash</td><td><code>' + info.bestBlockHash.substr(0, 16) + '...</code></td></tr>';
              html += '<tr><td>Peers</td><td>' + info.peers + '</td></tr>';
              html += '<tr><td>Mempool Txs</td><td>' + info.mempoolSize + '</td></tr>';
              html += '</table>';
            } else {
              html += '<p><strong>Error:</strong> ' + info.message + '</p>';
            }
            html += '</div>';
          }
          document.getElementById('status').innerHTML = html;
        }
        
        updateStatus();
        setInterval(updateStatus, 5000);
      </script>
    </body>
    </html>
  `);
});

app.listen(3002, () => console.log('Status page listening on port 3002'));
STATUS_EOF

# Create status package.json
cat > /opt/status/package.json << 'EOF'
{
  "name": "tg11-status",
  "version": "1.0.0",
  "description": "Network status page for TG11 testnet",
  "main": "status.js",
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF

cd /opt/status
npm install

# Create systemd service for status page
cat > /etc/systemd/system/status-page.service << EOF
[Unit]
Description=TG11 Status Page
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/status
ExecStart=/usr/bin/node /opt/status/status.js
Environment="RPC_NODE_1=$RPC_NODE_1"
Environment="RPC_NODE_2=$RPC_NODE_2"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable status-page
systemctl start status-page

# 4. Enable Apache2 and set up vhosts
echo "[4/4] Configuring Apache2 vhosts..."
a2enmod proxy
a2enmod proxy_http
a2enmod rewrite

echo "=== Deployment Complete ==="
echo "Faucet Service: http://localhost:3001"
echo "Status Page: http://localhost:3002"
echo "Next: Configure Apache2 vhosts for faucet.testnet.tg11.org and status.testnet.tg11.org"
