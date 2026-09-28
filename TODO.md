# TODO

## keytree rollout (started 2026-09-28)

SSH keys now come from [keytree](https://github.com/ragibkl/keytree) and
[server-keys](https://github.com/ragibkl/server-keys), replacing
`github-keys.sh` + `ssh-users/`. Per VM: run the installer, remove the
`AuthorizedKeysCommand` lines from sshd config, reload, test a fresh login,
delete `/usr/local/bin/github-keys.sh`.

- [x] vmbr1-alpine-k3s-worker-2
- [ ] vmbr1-alpine-k3s-worker-1
- [ ] vmbr1-alpine-k3s-server-1
- [ ] vmbr0-alpine-router-vmbr1 (ProxyJump to Proxmox: keep a session open)
- [ ] vmbr1-ubuntu-coder: keytree only manages root. The `ragib` user's
      keys come from cloud-init (static); add a `ragib` account entry in
      server-keys if those should follow GitHub too
- [ ] vmbr2 VMs (not reachable from the Coder workspace)

## alpine-jellyfin: data disk

Decommissioned 2026-09-27 (VM 231 powered off, start-at-boot off; see
`alpine-jellyfin/README.md`). The 3.7 TB data disk (`/mnt/sdb1`, ~1 TB used:
`shared/`, including `media/`) is still attached and intact.

- [ ] Decide what to keep from `/mnt/sdb1/shared`, then delete the VM and disk
