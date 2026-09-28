# TODO

## keytree rollout (started 2026-09-28)

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
- [ ] vmbr2.ingress.ragib.dev: probably never had github-keys.sh (Coder key
      refused). Install from a machine with access, with
      `--name vmbr0-alpine-frps-vmbr2`
- [ ] Stopped VMs still on github-keys.sh: vmbr0-alpine-ddns (100),
      vmbr1-alpine-jellyfin (231, to be deleted). Migrate or delete them,
      then delete `ssh-users/` (they fetch it at login).
- [ ] Each migrated VM has `/root/00_common.conf.bak` (the old sshd
      snippet); delete once settled.

On vmbr1-ubuntu-coder, keytree only manages root. The `ragib` user's keys
come from cloud-init (static), and root's cloud-init lines force "Please
login as ragib" for the keys on them; both left as they were.

## alpine-jellyfin: data disk

Decommissioned 2026-09-27 (VM 231 powered off, start-at-boot off; see
`alpine-jellyfin/README.md`). The 3.7 TB data disk (`/mnt/sdb1`, ~1 TB used:
`shared/`, including `media/`) is still attached and intact.

- [ ] Decide what to keep from `/mnt/sdb1/shared`, then delete the VM and disk
