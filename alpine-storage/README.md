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

Monitoring: after each run the script pushes the result to the vmbr1 Gatus
(external endpoints `storage_offsite-copy` / `storage_offsite-sync`, via the
`gatus-push` NodePort 30808, allowed only from this VM, bearer token in
`.env`). Gatus alerts on Telegram when a run fails, or when no push arrives
within 2 h (copy) / 26 h (sync). It also checks Garage's `/health`.

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

## Disaster recovery

Drilled 2026-09-30 (throwaway Garage on other ports: key import, 300-object
restore from Wasabi checked with `rclone check`, a deleted object found in
Wasabi's versions).

**Right away, if this VM or its SSD is gone:** point Nextcloud at Wasabi.
In flux-deploy `services/nextcloud/nextcloud.yaml`, set
`OBJECTSTORE_S3_HOST=s3.ap-southeast-1.wasabisys.com`, `PORT=443`,
`SSL=true`, `REGION=ap-southeast-1`, and the key/secret refs back to
`OBJECTSTORE_S3_KEY/SECRET` (the Wasabi IAM user `nextcloud`). Wasabi is
at most an hour behind (hourly copy); uploads since the last copy are lost.

**Rebuilding Garage:**

1. New disk or VM, then Setup above (a fresh `meta/`).
2. Recreate each app's key with its **old ID and secret**, from where the
   app keeps them (for Nextcloud: `GARAGE_S3_KEY/SECRET` in
   `nextcloud-secrets`), so the app's config doesn't change:
   `$G key import --yes <id> <secret> -n nextcloud`. This only works on a
   fresh Garage: one that has seen the ID, even deleted, refuses it.
3. `$G bucket create cloud-bancuh-s3`, allow the key, and a new
   `offsite-sync` key for `rclone-cron/.env`.
4. Copy back from Wasabi with a temporary write key (`initial-copy.sh`,
   about an hour for ~200 GB at full speed; drop the bandwidth cap).
   Keep rclone-cron's jobs **commented out** until the copy is complete:
   a Garage -> Wasabi sync from a half-filled Garage would delete from
   Wasabi (`--max-delete 2000` limits the damage, versioning keeps it
   recoverable).
5. Check with `rclone size` / `rclone check` on both sides, switch
   Nextcloud back to Garage, re-enable the jobs.

**Recovering a deleted or overwritten object from Wasabi** (versioning;
needs the Wasabi admin user, as the bucket-scoped keys can't touch
versions): `aws s3api list-object-versions --bucket cloud-bancuh-s3 --prefix
urn:oid:<fileid>`, then delete the delete marker (`delete-object --key ...
--version-id <marker>`) or copy the old version back. The Wasabi IAM
endpoint (`iam.wasabisys.com`) needs region `us-east-1`.

Nextcloud's database is not here: it's on Longhorn with nightly backups to
Wasabi (the cluster's Longhorn backup target).

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
