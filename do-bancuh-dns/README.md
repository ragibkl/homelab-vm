# do-bancuh-dns

Rebuilding the Bancuh DNS nodes on DigitalOcean (`sg-dns1`, `sg-dns2`, region
`sgp1`) onto a fresh Ubuntu, while keeping their addresses. Both were moved
from Ubuntu 16.04 to 24.04 this way on 2026-09-29.

A DigitalOcean **rebuild** replaces the droplet's disk but keeps the droplet:
same ID, same public IPv4, same reserved IP, same IPv6. That matters because
users may have any of those typed into their routers, and IPv6 can't be moved
to another droplet.

| File | What it's for |
|---|---|
| `rebuild-node.sh` | Run from a workstation: backup, rebuild, setup, checks |
| `setup-node.sh` | Runs on the fresh node: resolver, Docker, adblock-dns-server, restore, keytree |
| `base-image/` | The two files baked into the base snapshot (below) |

## Rebuilding a node

Needs `doctl` (authenticated), `python3`, and SSH as root to the node.

```shell
SSH_KEY=~/.ssh/id_ed25519 ./rebuild-node.sh sg-dns1 71746677 247551413 sg-dns2
```

Arguments: node, droplet ID, base snapshot ID, partner node. It stops if the
partner isn't answering, backs up `.env` and the `letsencrypt` volume, rebuilds,
runs `setup-node.sh`, and prints what users saw on port 53. Do one node at a
time; the partner covers the region.

Measured on 2026-09-29:

| | sg-dns2 | sg-dns1 |
|---|---|---|
| DNS down | 10 min (password lock, see below) | 1 min 57 s |
| Answering unfiltered (blocklist compiling, adblock-dns-server#220) | 1 min 48 s | 1 min 30 s |

Afterwards, check from outside: 53 over UDP and TCP, DoT (853), DoH (443,
HTTP/2 only), a blocked name answering `0.0.0.0`, 1153 closed, and IPv6.
This workspace has no IPv6, so test IPv6 from another node (jp-dns1 works;
fr-dns1 can't reach DigitalOcean over IPv6).

**Rollback:** rebuild from the node's pre-upgrade snapshot
(`sg-dnsN-pre-upgrade-2026-09-29`); addresses stay the same.

## The base image

Snapshot `sg-base-ubuntu-24.04-keys-v3` (ID 247551413, `sgp1`): DigitalOcean's
Ubuntu 24.04 plus:

- the DigitalOcean account keys in root's `authorized_keys` (`ragib-x390`,
  `ragib-t14sg3`, `coder-workspace`)
- `base-image/root-keys-only.service`, enabled
- `base-image/01-keys-only.conf` in `/etc/ssh/sshd_config.d/`

Why not rebuild straight from DigitalOcean's Ubuntu image: `sg-dns1` and
`sg-dns2` were created without DigitalOcean SSH keys. On a rebuild,
DigitalOcean then writes a new root password into `/etc/shadow`, emails it, and
marks it must-change. sshd enforces that even for key logins ("Password change
required but no TTY available"), so nothing can log in without the emailed
password. cloud-init also switches SSH password login on. Neither can be turned
off in cloud-init config: the password is written to disk before boot.
`root-keys-only.service` undoes it at boot, before sshd starts, and
`01-keys-only.conf` keeps password login off.

To recreate it: create a droplet from `ubuntu-24-04-x64` in `sgp1` with the
account SSH keys, copy the two files in, `systemctl enable
root-keys-only.service`, power off, snapshot. Test it by rebuilding a droplet
created **without** SSH keys: key login must work straight away.

## What setup-node.sh deals with

- `systemd-resolved` takes port 53, so dnsdist can't start: disabled, with a
  static `/etc/resolv.conf` (adblock-dns-server README, "Disabling
  systemd-resolve"). It writes a real file, because a dangling stub symlink
  leaves the host with no resolver. The host then quietly resolves through its
  own dnsdist, which works until the filter restarts and can't fetch its
  config.
- Docker from Docker's own repository, with Compose v2.
- The old node's `.env` and `letsencrypt` volume, so DoT/DoH keep the same
  certificate and ACME account. The volume also holds a stale certbot-era
  `live/` certificate; the one served is newer, so check expiry with
  `openssl s_client` on port 853, not from the files.
- keytree, with `--name` set to the node (the droplet hostname can differ).

## In-place upgrade (tested, not used)

`do-release-upgrade` 16.04 → 24.04 also works and keeps everything, tested on
a copy of sg-dns2. It's slower (four upgrades of ~17 min) and has traps: the
16.04 upgrader rejects `mirrors.digitalocean.com` as "unknown mirror" (switch
sources to `archive.ubuntu.com` first), `systemd-resolved` appears in 18.04,
the 24.04 upgrade replaces `/etc/resolv.conf` with a stub symlink, and the old
`docker-compose` v1 is removed along the way. The rebuild was simpler.
