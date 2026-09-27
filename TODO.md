# TODO

## github-keys.sh: keep the key cache across reboots (parked 2026-09-27)

`github-keys.sh` caches the fetched keys in `/tmp/github-keys-<network>.txt`
and falls back to that cache when GitHub can't be reached. On these VMs `/tmp`
is tmpfs, so the cache is gone after every reboot — and root's
`authorized_keys` is empty (checked on vmbr1-alpine-k3s-server-1), so there
is no other key.

Lockout needs both at once: a VM that has just rebooted, and no way for it to
reach GitHub at login (home internet down, the VM's DNS broken, GitHub down).
That is exactly when you would want to SSH in to fix things; the Proxmox
console is then the only way in.

Fix: move `CACHE_FILE` to `/var/cache/github-keys/` (persistent, `0700`,
root-owned). New laptop keys added to GitHub still show up within the hour,
so the workflow does not change. Then push the updated script to the running
VMs (`install -m 0755 github-keys.sh /usr/local/bin/`); the Ubuntu VM reuses
the same file.

Optional hardening, not required once the cache persists:

- a break-glass key in `/root/.ssh/authorized_keys`
- a dedicated unprivileged `AuthorizedKeysCommandUser` instead of root
- branch protection on `master`: anyone who can push `ssh-users/*.txt` gets
  root on every VM within an hour

## alpine-jellyfin: data disk

Decommissioned 2026-09-27 (VM 231 powered off, start-at-boot off; see
`alpine-jellyfin/README.md`). The 3.7 TB data disk (`/mnt/sdb1`, ~1 TB used:
`shared/`, including `media/`) is still attached and intact.

- [ ] Decide what to keep from `/mnt/sdb1/shared`, then delete the VM and disk
