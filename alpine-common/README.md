# alpine-common

Alpine common setup.

## Setup

```shell
apk add git
git clone https://github.com/ragibkl/homelab-vm.git

cd homelab-vm/alpine-common
./setup.sh
```

## Growing the disk

After increasing the disk size in Proxmox:

```shell
./resize-disk.sh
```

Grows the root partition (`/dev/sda3`, the last one on the disk) and its
filesystem to fill the disk. Fails with NOCHANGE if there is nothing to grow.


## TRIM

`setup.sh` installs the `fstrim` package (busybox `fstrim` has no `-a`) and
`fstrim` into `/etc/periodic/weekly` (crond runs it
Saturdays 03:00; log tag `fstrim`). Alpine has no trim job of its own, and
without one, deleted data stays allocated in the Proxmox thin pool. The
Proxmox disk needs `discard=on,ssd=1` for the TRIM to get through. On k3s
nodes it also trims mounted Longhorn volumes.

## SSH keys (keytree)

`setup.sh` installs [keytree](https://github.com/ragibkl/keytree), which
syncs root's `authorized_keys` hourly from
[server-keys](https://github.com/ragibkl/server-keys). The hostname must
match an entry there (`vmbr1-*` and so on).

To move a VM that still uses the old `github-keys.sh`, run from a machine
that can already SSH in:

```shell
./migrate-to-keytree.sh 10.15.1.21
./migrate-to-keytree.sh 10.15.2.11 -J 10.15.1.1,10.15.0.196   # vmbr2, via both routers
```

It keeps a spare SSH connection open while it changes sshd, tests a fresh
login, and puts the old config back if that login fails.

To upgrade keytree, re-run the installer with no arguments: it keeps
`/etc/keytree/config.yaml` (including any `name:`).

```shell
wget -qO- https://ragibkl.github.io/keytree/install | sh
```
