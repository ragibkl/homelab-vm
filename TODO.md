# TODO

## keytree rollout (done 2026-09-29)

SSH keys now come from [keytree](https://github.com/ragibkl/keytree) and
[server-keys](https://github.com/ragibkl/server-keys), replacing
`github-keys.sh` + `ssh-users/`. Per VM: run the installer, remove the
`AuthorizedKeysCommand` lines from sshd config, reload, test a fresh login,
delete `/usr/local/bin/github-keys.sh`.

Done 2026-09-28 (all running VMs; `sshd -T` shows no key command on each):

- [x] vmbr1: router-vmbr1, k3s-server-1, k3s-worker-1/2, ubuntu-coder,
      alpine-ingress (openvpn VM, 10.15.1.254)
- [x] vmbr0: alpine-ingress (openvpn VM, 10.15.0.254), router-vmbr2
      (10.15.0.196; also had the lines in its main `sshd_config`)
- [x] vmbr2: k3s-server-1, k3s-worker-1/2, alpine-openvpn (reached with
      `ssh -J 10.15.1.1,10.15.0.196 10.15.2.x`)
- [x] vmbr1.ingress.ragib.dev (vmbr0-alpine-frps-vmbr1)
- [x] vmbr2.ingress.ragib.dev (vmbr0-alpine-frps-vmbr2)
- [x] vmbr0-alpine-ddns (100): deleted 2026-09-29 (no longer needed).
- [x] `ssh-users/` deleted 2026-09-29: no VM runs github-keys.sh any more
      (all 13 running VMs checked with `sshd -T`; no stopped VMs left).
- [x] vmbr1-alpine-jellyfin (231): keytree 2026-09-29; it had no key
      command, only a static authorized_keys. Renamed vmbr1-alpine-storage
      (Garage), see alpine-storage/.
- [x] `/root/*.bak` sshd backups removed from the migrated VMs (2026-09-29,
      during the keytree v0.2.0 upgrade).

On vmbr1-ubuntu-coder, keytree only manages root. The `ragib` user's keys
come from cloud-init (static), and root's cloud-init lines force "Please
login as ragib" for the keys on them; both left as they were.

## alpine-jellyfin: data disk

Decommissioned 2026-09-27 (VM 231 powered off, start-at-boot off; see
`alpine-jellyfin/README.md`). The 3.7 TB data disk (`/mnt/sdb1`, ~1 TB used:
`shared/`, including `media/`) is still attached and intact.

- [ ] Decide what to keep from `/mnt/sdb1/shared`, then delete the VM and disk
