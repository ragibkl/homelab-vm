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

Single node, `replication_factor = 1`: Garage keeps one copy. Durability
comes from the offsite copy of each bucket to Wasabi (`rclone-cron/`), which
is also the fallback endpoint if this VM is lost.

| Port | What | Who uses it |
| ---- | ---- | ----------- |
| 3900 | S3 API, region `garage`, path-style | apps on vmbr1 (`http://10.15.1.157:3900`) |
| 3903 | admin API: `/health` (open), `/metrics` (metrics token) | Gatus |

## Layout

Two independent compose projects, both under `/root/storage` on the VM:

```
/root/storage/
├── garage/        Garage itself (docker-compose.yaml, garage.toml, .env)
└── rclone-cron/   rclone + crond: offsite copy to Wasabi
                   (docker-compose.yaml, crontab, offsite-sync.sh,
                    initial-copy.sh, .env, state/)
```

Secrets are only in each folder's `.env` on the VM (see `sample.env`).

## Setup: garage

```sh
mkdir -p /root/storage/garage /mnt/sdb1/garage/meta /mnt/sdb1/garage/data
# copy garage/ to /root/storage/garage
cd /root/storage/garage
cp sample.env .env    # fill in: openssl rand -hex 32 for each
docker compose up -d

G="docker compose exec -T garage /garage"
$G status                                     # note the node ID
$G layout assign -z home -c 2.5T <node-id>    # capacity is only a weight on one node
$G layout apply --version 1
```

## Buckets and keys

One bucket per app, and one key per job, allowed on that bucket only (a
leaked key exposes one app). Permissions are read / write / owner per
bucket; no app key gets owner or `--create-bucket`. Garage keeps secrets in
its metadata (`$G key info <key> --show-secret`), and `$G key import` can
recreate a key with the same ID and secret after a rebuild.

| Bucket | Key | Permissions | Secret lives in |
| ------ | --- | ----------- | --------------- |
| `cloud-bancuh-s3` (Nextcloud) | `nextcloud` | read, write | flux-deploy `nextcloud-secrets` (SOPS): `GARAGE_S3_KEY/SECRET` |
| `cloud-bancuh-s3` | `offsite-sync` | read | `rclone-cron/.env` |

The bucket name must stay `cloud-bancuh-s3`: Nextcloud's storage id
(`object::store:amazon::cloud-bancuh-s3`) contains it.

```sh
$G bucket create <bucket>
$G key create <name>                  # prints the key ID and secret
$G bucket allow --read --write <bucket> --key <name>
$G bucket info <bucket>
```

## Offsite copy: rclone-cron

`offsite-sync.sh copy|sync` copies each bucket in its `BUCKETS` list from
Garage to Wasabi (read-only Garage key; the Wasabi key is the bucket-scoped
IAM user). `crontab` runs `copy` hourly (upload new and changed objects,
never delete) and `sync` nightly at 04:00 (also mirror deletions; the Wasabi
bucket has versioning, so deleted versions stay recoverable, and
`--max-delete 2000` stops a sync from an accidentally empty source). Each
success writes the time to `state/last-copy` / `state/last-sync`.

Enabled 2026-09-30, when Nextcloud moved to Garage. Before cutting over
another app, keep its bucket out of `BUCKETS` in `offsite-sync.sh`: until
then Wasabi is its live storage, and a sync would delete from it what
Garage doesn't have yet.

Moving an existing bucket in from Wasabi (before cutover), with a temporary
Garage key with write access in `RCLONE_CONFIG_GARAGEW_*`:

```sh
$G key create initial-copy --expires-in 2d
$G bucket allow --read --write <bucket> --key initial-copy
docker compose exec -T rclone-cron initial-copy.sh <bucket> 30M   # 30 MiB/s ~ 250 Mbit/s
```

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
