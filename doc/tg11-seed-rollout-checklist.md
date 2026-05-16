# TG11 Seed Rollout Checklist

Use this checklist when bringing up public TG11 seed/full-relay nodes.

## Preflight

- Confirm DNS hostnames reserved:
  - `seed1.tg11.org`
  - `seed2.tg11.org`
  - `seed3.tg11.org`
- Confirm each node has static public IPv4 (and IPv6 if available).
- Confirm each node can accept inbound `31111/tcp`.

## Provision

On each node:

1. Create service user and datadir.
2. Deploy TG11 binaries (or clone/build from this repo).
3. Generate config using setup script.

Example:

```bash
contrib/nodeops/setup-tg11-node.sh seed1 seed1.tg11.org --role seed --datadir /var/lib/tg11-seed1
```

## Configure peers

Ensure each seed has at least two static peers:

```ini
addnode=seed1.tg11.org:31111
addnode=seed2.tg11.org:31111
addnode=seed3.tg11.org:31111
```

## Firewall

```bash
contrib/nodeops/firewall-ufw.sh seed
```

## Service enablement

1. Install `contrib/nodeops/systemd/tg11d.service` into `/etc/systemd/system/tg11d.service`.
2. Adjust `ExecStart`, `ExecStop`, and datadir paths.
3. Run:

```bash
sudo systemctl daemon-reload
sudo systemctl enable tg11d
sudo systemctl start tg11d
sudo systemctl status tg11d
```

## Validation

- `tg11-cli getnetworkinfo` returns expected local version and peers.
- `tg11-cli getpeerinfo` shows cross-connections between seed nodes.
- `tg11-cli getblockchaininfo` is not stuck in initial blocks forever.
- New public node can sync using only seed hostnames.

## DNS cutover

- Publish `A`/`AAAA` records for seed hosts.
- Keep low TTL (e.g., 300) during initial rollout.
- After 24-48h stable operation, increase TTL.

## Post-rollout

- Monitor uptime, peer count, orphan rate, and disk growth.
- Keep one extra standby node definition ready for failover.
