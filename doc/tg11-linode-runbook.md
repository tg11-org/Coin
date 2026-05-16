# TG11 Linode Temporary Runbook (Nanode 1 GB)

This runbook is for temporary TG11 mainnet operations on low-cost Linode nodes.

## Suggested layout

- `seed1.tg11.org` -> seed role
- `seed2.tg11.org` -> seed role
- `seed3.tg11.org` -> seed role
- `rpc1.tg11.org` -> private-rpc role
- `rpc2.tg11.org` -> private-rpc role

All profiles are configured to be lightweight and pruned by default.

## One-shot install commands

From repo root on each host:

```bash
# seed nodes
contrib/nodeops/install-and-enable-tg11-node.sh seed1 seed1.tg11.org --role seed --setup-firewall --addnode seed2.tg11.org:31111 --addnode seed3.tg11.org:31111
contrib/nodeops/install-and-enable-tg11-node.sh seed2 seed2.tg11.org --role seed --setup-firewall --addnode seed1.tg11.org:31111 --addnode seed3.tg11.org:31111
contrib/nodeops/install-and-enable-tg11-node.sh seed3 seed3.tg11.org --role seed --setup-firewall --addnode seed1.tg11.org:31111 --addnode seed2.tg11.org:31111

# private rpc node
contrib/nodeops/install-and-enable-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --setup-firewall --rpc-cidr 10.10.0.0/16
contrib/nodeops/install-and-enable-tg11-node.sh rpc2 rpc2.tg11.org --role private-rpc --setup-firewall --rpc-cidr 10.10.0.0/16
```

## Daily operations

```bash
sudo systemctl status tg11d-seed1.service
sudo systemctl restart tg11d-seed1.service
sudo journalctl -u tg11d-seed1.service -n 200 --no-pager
```

## Fleet orchestration (all nodes)

Use the inventory file and orchestrator when you want to run one action across all temporary Linodes.

Inventory template:

- `contrib/nodeops/fleet/hosts.example.tsv`

Run all installs from your control machine:

```bash
contrib/nodeops/fleet-orchestrate.sh --action install --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11
```

Or run everything in one pass (prepare repos + install + verify):

```bash
contrib/nodeops/fleet-bootstrap-all.sh --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11 --repo-url https://github.com/TrentonGage11/Coin.git
```

Run all updates:

```bash
contrib/nodeops/fleet-orchestrate.sh --action update --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11
```

Run all verifications:

```bash
contrib/nodeops/fleet-orchestrate.sh --action verify --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11
```

## Update workflow

```bash
contrib/nodeops/update-tg11-node.sh /opt/tg11 tg11d-seed1.service

# rpc nodes
contrib/nodeops/update-tg11-node.sh /opt/tg11 tg11-rpc1.service
contrib/nodeops/update-tg11-node.sh /opt/tg11 tg11-rpc2.service
```

If wallet binary is needed on a node:

```bash
contrib/nodeops/update-tg11-node.sh /opt/tg11 tg11-rpc1.service --build-wallet
```

## Health checks

```bash
/opt/tg11/src/tg11-cli -datadir=/var/lib/tg11-seed1 getblockchaininfo
/opt/tg11/src/tg11-cli -datadir=/var/lib/tg11-seed1 getnetworkinfo
/opt/tg11/src/tg11-cli -datadir=/var/lib/tg11-seed1 getpeerinfo

# or use helper
contrib/nodeops/verify-tg11-node.sh /var/lib/tg11-seed1 tg11d-seed1.service /opt/tg11/src/tg11-cli
```
