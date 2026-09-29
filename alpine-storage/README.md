# alpine-storage

Self-hosted S3 ([Garage](https://garagehq.deuxfleurs.fr/)) for the homelab,
on `vmbr1-alpine-storage` (Proxmox VM 231, `10.15.1.157`, vmbr1). This was
`vmbr1-alpine-jellyfin` until 2026-09-29; it keeps that VM's 3.7 TB SSD
(passed through as `/dev/sdb`, mounted at `/mnt/sdb1`). The old media in `/mnt/sdb1/shared`
stays where it is; Jellyfin and Transmission are not run.

```
/mnt/sdb1/
├── shared/media/    movies, tv-shows (anime deleted 2026-09-29)
└── garage/
    ├── meta/        Garage metadata (LMDB) + 6-hourly snapshots
    └── data/        object data
```

Single node, `replication_factor = 1`: Garage keeps one copy. Durability is
meant to come from an offsite sync of each bucket (planned: nightly rclone to
a versioned Wasabi bucket), which also serves as a fallback endpoint if this
VM is lost.

| Port | What | Who uses it |
| ---- | ---- | ----------- |
| 3900 | S3 API, region `garage`, path-style | apps on vmbr1 (`http://10.15.1.157:3900`) |
| 3903 | admin API: `/health` (open), `/metrics` (metrics token) | Gatus |

## Setup

As root on the VM (Docker with the Compose plugin):

```sh
mkdir -p /root/garage /mnt/sdb1/garage/meta /mnt/sdb1/garage/data
# copy docker-compose.yaml and garage.toml to /root/garage
cd /root/garage
cp sample.env .env    # fill in: openssl rand -hex 32 for each
docker compose up -d

G="docker compose exec -T garage /garage"
$G status                                     # note the node ID
$G layout assign -z home -c 2.5T <node-id>    # capacity is only a weight on one node
$G layout apply --version 1
```

## One bucket and one key per app

Each app gets its own bucket and its own key, allowed on that bucket only, so
a leaked key exposes one app's data:

```sh
$G bucket create nextcloud
$G key create nextcloud                # prints the key ID and secret once
$G bucket allow --read --write nextcloud --key nextcloud
$G bucket info nextcloud
```

Put the key into the app's SOPS secret in flux-deploy; don't keep it here.

Useful: `$G bucket list`, `$G key list`, `$G stats`, `$G worker list`.

## The SSD needs TRIM

The data disk is a Transcend TS4TSSD230S passed through from Proxmox. Until
2026-09-29 its Proxmox entry had no `discard=on`, so QEMU dropped the guest's
TRIM: after years of downloads the drive treated ~3 TB of deleted data as
live and wrote at 1-2 MB/s (17 s per 1 MB write), running at 70-78 °C, and
once stalled long enough for ext4 to go read-only. With TRIM passed through
and one `fstrim` (2.9 TB + 0.7 TB released), it writes at 300-500 MB/s.

- Proxmox: `scsi2: /dev/disk/by-id/ata-TS4TSSD230S_H690001077,discard=on,ssd=1`
  (and `discard=on,ssd=1` on the boot disk `scsi0` too)
- VM: `/etc/periodic/weekly/fstrim` from alpine-common (log tag `fstrim`).
- It still runs hot (72-75 °C under load): check its airflow.

## Upgrading Garage

Bump the image tag in `docker-compose.yaml`, then `docker compose pull &&
docker compose up -d`. Read the release notes first: major versions can
need a metadata migration.

## Notes

- SSH: keytree; the hostname `vmbr1-alpine-storage` matches `vmbr1-*` in
  server-keys.
- Alpine 3.24 (upgraded in place from 3.17 on 2026-09-29, one release at a
  time), Docker 29 with Compose v2. Starts at boot (`onboot: 1`).
- `autoresize` shows as crashed in `rc-status`: it's a one-shot script from
  the template (grow the root partition), which OpenRC reports that way once
  it exits. Harmless.
