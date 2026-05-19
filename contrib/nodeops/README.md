# TG11 Node Operations Assets

This folder contains practical templates and scripts for running TG11 nodes in production-like environments.

## Files

- `bootstrap-tg11-node.sh`: Initializes a TG11 datadir and writes a role-based config.
- `setup-tg11-node.sh`: Friendly wrapper for named nodes, e.g. `seed1 seed1.tg11.org`.
- `install-and-enable-tg11-node.sh`: One-shot installer (config + systemd + optional firewall).
- `update-tg11-node.sh`: Pull/rebuild/restart workflow helper.
- `verify-tg11-node.sh`: Local post-deploy/update health checks.
- `fleet-orchestrate.sh`: Multi-host SSH orchestrator for install/update/verify.
- `fleet-bootstrap-all.sh`: One-command wrapper to prepare repos + install + verify fleet.
- `fleet/hosts.example.tsv`: Example host inventory for fleet orchestration.
- `package-release.sh`: Builds a versioned binary release archive and checksum file.
- `public-testnet-bootstrap.sh`: Boots a public testnet fleet from an inventory TSV.
- `mainnet-candidate-check.sh`: Checks launch-readiness docs and freeze items.
- `fleet/public-testnet-hosts.example.tsv`: Example inventory for a public testnet.
- `tg11-mainnet-seed.conf`: Public seed/full-relay node template.
- `tg11-mainnet-full.conf`: Public full node template with optional RPC disabled by default.
- `tg11-mainnet-private-rpc.conf`: Private node template for wallet/indexer/backend RPC use.
- `firewall-ufw.sh`: Applies role-based UFW rules.
- `systemd/tg11d.service`: Systemd unit template.

## Quick start

```bash
# From repo root
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed
# or
contrib/nodeops/setup-tg11-node.sh full1 full1.tg11.org --role full
# or
contrib/nodeops/setup-tg11-node.sh rpc1 rpc1.tg11.org --role private-rpc --datadir /srv/tg11-rpc1

# also install and enable systemd service for auto-start on reboot
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed --install-systemd

# one-shot install including service install/enable/start and firewall
contrib/nodeops/install-and-enable-tg11-node.sh seed1 seed1.tg11.org --role seed --setup-firewall
```

Generate a unit file without installing it:

```bash
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed --write-service-file /tmp/tg11d-seed1.service
```

After install, update flow is:

```bash
git pull
sudo systemctl restart tg11d-seed1.service
```

One-command update helper:

```bash
contrib/nodeops/update-tg11-node.sh /opt/tg11 tg11d-seed1.service
```

Post-update verification:

```bash
contrib/nodeops/verify-tg11-node.sh /var/lib/tg11-seed1 tg11d-seed1.service /opt/tg11/src/tg11-cli
```

Fleet orchestration (all Linodes):

```bash
# first pass install
contrib/nodeops/fleet-orchestrate.sh --action install --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11

# rolling update pass
contrib/nodeops/fleet-orchestrate.sh --action update --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11

# post-update verification pass
contrib/nodeops/fleet-orchestrate.sh --action verify --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11
```

One-command full bootstrap (clone/pull + install + verify):

```bash
contrib/nodeops/fleet-bootstrap-all.sh --inventory contrib/nodeops/fleet/hosts.example.tsv --repo-root /opt/tg11 --repo-url https://github.com/TrentonGage11/Coin.git
```

After bootstrapping, edit the generated `litecoin.conf` and fill placeholders like:

- `externalip`
- `rpcbind`
- `rpcallowip`
- `rpcuser` / `rpcpassword`
- `addnode`

Then run `tg11d` with the datadir:

```bash
src/tg11d -datadir=/var/lib/tg11
```
