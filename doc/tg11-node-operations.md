# TG11 Node Operations Guide

This guide explains how TG11 nodes work and how to deploy them for `tg11.org`.

## Node roles

### 1) Seed/public relay node

- Purpose: bootstrap peers and keep the network discoverable.
- Typical hostname: `seed1.tg11.org`, `seed2.tg11.org`, `seed3.tg11.org`.
- Inbound: yes (`31111/tcp`).
- RPC: localhost only.

### 2) Public full node

- Purpose: validate and relay blocks/transactions.
- Can serve explorers and public APIs behind a proxy.
- Inbound: yes (`31111/tcp`).
- RPC: usually localhost/private network only.

### 3) Private RPC node

- Purpose: wallet backend, indexer, or internal services.
- Inbound P2P: optional/no.
- RPC: private network only, never exposed publicly.

## TG11 network values

- Mainnet P2P port: `31111`
- Mainnet RPC port: `31110`
- Testnet P2P/RPC: `31112` / `31120`
- Regtest P2P/RPC: `31113` / `31130`

## Recommended initial topology

- 3 public seed/full nodes across different providers/regions.
- 1-2 private RPC nodes for services.
- Optional: one warm standby node for failover.

## Temporary Linode 1 GB plan (recommended)

For your temporary environment, a good path is:

- `seed1.tg11.org`: seed role (pruned)
- `seed2.tg11.org`: seed role (pruned)
- `seed3.tg11.org`: seed role (pruned)
- `rpc1.tg11.org`: private-rpc role (pruned)

Notes:

- This works on low-cost 1 GB instances.
- For explorer/indexer workloads (`txindex=1`, non-pruned), move at least one node to a larger VM with larger disk.

## Bootstrap a node from this repo

From repo root:

```bash
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed
contrib/nodeops/setup-tg11-node.sh seed2 seed2.tg11.org --role seed
contrib/nodeops/setup-tg11-node.sh seed3 seed3.tg11.org --role seed
contrib/nodeops/setup-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --datadir /srv/tg11-rpc1

# auto-install service and enable startup on reboot
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed --install-systemd

# one-shot install (recommended for fresh hosts)
contrib/nodeops/install-and-enable-tg11-node.sh seed1 seed1.tg11.org --role seed --setup-firewall
```

Equivalent low-level command with flags:

```bash
contrib/nodeops/bootstrap-tg11-node.sh --role seed --name seed1 --fqdn seed1.tg11.org --datadir /var/lib/tg11-seed1
```

Then launch:

```bash
src/tg11d -datadir=/var/lib/tg11
```

Check health:

```bash
src/tg11-cli -datadir=/var/lib/tg11 getblockchaininfo
src/tg11-cli -datadir=/var/lib/tg11 getnetworkinfo
src/tg11-cli -datadir=/var/lib/tg11 getpeerinfo
```

## DNS seed notes

At first launch, static `addnode=` entries are enough. After stable uptime, move to DNS seeding for better decentralization.

Suggested records:

- `seed1.tg11.org A <ip1>`
- `seed2.tg11.org A <ip2>`
- `seed3.tg11.org A <ip3>`

In configs, keep:

```ini
dnsseed=1
addnode=seed1.tg11.org:31111
addnode=seed2.tg11.org:31111
addnode=seed3.tg11.org:31111
```

## Firewall baseline

Seed/public full node:

- Allow inbound `31111/tcp`.
- Restrict RPC (`31110/tcp`) to localhost/private ranges only.

Private RPC node:

- Deny public inbound RPC.
- Allow RPC only from your app subnet/VPN.

## Systemd service example

```ini
[Unit]
Description=TG11 daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=tg11
Group=tg11
ExecStart=/opt/tg11/src/tg11d -daemon -datadir=/var/lib/tg11 -pid=/var/lib/tg11/tg11d.pid
ExecStop=/opt/tg11/src/tg11-cli -datadir=/var/lib/tg11 stop
PIDFile=/var/lib/tg11/tg11d.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Template file is available at:

- `contrib/nodeops/systemd/tg11d.service`

The setup wrapper can generate and install a per-node service automatically.

Examples:

```bash
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed --install-systemd
contrib/nodeops/setup-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --install-systemd --service-name tg11-rpc1
```

Update workflow on a node:

```bash
git pull
sudo systemctl restart tg11d-seed1.service
sudo systemctl status tg11d-seed1.service
```

Or use helper script:

```bash
contrib/nodeops/update-tg11-node.sh /opt/tg11 tg11d-seed1.service
```

## Firewall helper

UFW helper script is available at:

- `contrib/nodeops/firewall-ufw.sh`

Examples:

```bash
contrib/nodeops/firewall-ufw.sh seed
contrib/nodeops/firewall-ufw.sh private-rpc 10.10.0.0/16
```

## Security checklist

- Use unique strong `rpcuser`/`rpcpassword` per node.
- Keep RPC bound to private addresses or localhost.
- Patch OS and dependencies regularly.
- Run node under a non-root user.
- Back up `wallet.dat` only if that node holds funds.
- Monitor disk, RAM, and peer count.

## Upgrade workflow

1. Build and test on a staging node.
2. Upgrade one seed node first.
3. Observe for at least one day.
4. Roll remaining nodes in batches.

## What this project provides

This project provides the node daemon (`tg11d`), CLI (`tg11-cli`), templates, and deployment runbook. You do not need a separate codebase for nodes.
