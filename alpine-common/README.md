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

