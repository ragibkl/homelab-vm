# ubuntu-common

Ubuntu common setup. The Ubuntu counterpart of `alpine-common`, for VMs that
need something Alpine cannot do (e.g. Sysbox for `ubuntu-coder`).

Reuses `alpine-common/sshd_config_common.conf` and `daemon.json`, and
installs [keytree](https://github.com/ragibkl/keytree) like the Alpine VMs,
so SSH keys and Docker log rotation work the same.

## Creating the VM

Built from the Ubuntu 24.04 cloud image with cloud-init, on the Proxmox host:

```shell
# once: image kept in /root/cloudimg/ on the Proxmox host
cd /root/cloudimg
curl -fO https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
curl -fO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
grep ' \*noble-server-cloudimg-amd64.img$' SHA256SUMS | sha256sum -c -
curl -f https://github.com/ragibkl.keys -o ragibkl.keys

# per VM (example: vmbr1-ubuntu-coder)
ID=1031
qm create $ID --name vmbr1-ubuntu-coder --ostype l26 --machine q35 \
  --cores 4 --sockets 1 --cpu host --numa 0 --memory 8192 --balloon 0 \
  --scsihw virtio-scsi-single --net0 virtio,bridge=vmbr1,firewall=1 \
  --agent enabled=1 --onboot 1 --serial0 socket --vga serial0
qm set $ID --scsi0 local-lvm:0,import-from=/root/cloudimg/noble-server-cloudimg-amd64.img,discard=on,iothread=1,ssd=1
qm resize $ID scsi0 100G
qm set $ID --ide2 local-lvm:cloudinit --boot order=scsi0
qm set $ID --ciuser ragib --sshkeys /root/cloudimg/ragibkl.keys \
  --ipconfig0 ip=10.15.1.31/24,gw=10.15.1.1 --nameserver 10.15.1.1 --ciupgrade 1
qm start $ID
```

The hostname must match an entry in
[server-keys](https://github.com/ragibkl/server-keys) (`vmbr1-*`): keytree
uses it to decide who can log in.

## Setup

```shell
sudo apt-get install -y git
git clone https://github.com/ragibkl/homelab-vm.git

cd homelab-vm/ubuntu-common
sudo ./setup.sh

# only if the VM runs Sysbox containers
sudo ./install-sysbox.sh
```
