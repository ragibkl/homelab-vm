# TODO

## Coder VM on vmbr1

Self-hosted [Coder](https://coder.com/) with workspaces running as
[Sysbox](https://github.com/nestybox/sysbox) containers, so each workspace can
run its own Docker (and systemd) without `--privileged`.

This is the first **Ubuntu** VM here. Everything else is Alpine, and
`alpine-common/setup.sh` does not apply (apk/OpenRC). A new `ubuntu-common/`
(or `ubuntu-coder/` doing its own base setup) is needed.

### Why Ubuntu

Sysbox has no Alpine package. Its supported hosts are Ubuntu/Debian/Flatcar.

- **Ubuntu 24.04 (Noble)**, kernel 6.8+: supported by Sysbox, no shiftfs
  needed. Sysbox **v0.7.1** (2026-07-31) specifically fixed Noble mount
  failures, so do not go below that.
- Check first: https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md

### VM

| | |
|---|---|
| Hostname | `vmbr1-ubuntu-coder` — `github-keys.sh` picks `ssh-users/<prefix>.txt` from the text before the first `-`, so the `vmbr1-` prefix matters |
| VMID | `1031` (created 2026-09-27) — follows the ID→IP pattern of the k3s VMs (`1021` → `.21`) |
| IP | `10.15.1.31`, static via cloud-init (outside the dnsmasq DHCP range `.100–.200`) |
| CPU | 4 vCPU |
| RAM | **8 GB** to start (see below) |
| Disk | 100 GB on `local-lvm`, grow later with growpart/resize2fs |

**RAM budget, 8 GB:**

- Ubuntu + dockerd + sysbox-mgr/sysbox-fs: ~0.7 GB
- Coder server + Postgres: ~0.5–0.8 GB
- Per Sysbox workspace: systemd + inner dockerd ~0.2–0.3 GB, VS Code server
  ~0.5 GB, then whatever you run — rust-analyzer 1–3 GB, tsserver ~1 GB,
  builds spike beyond that.

So 8 GB is one heavy (Rust) or two light workspaces at a time. If you run
`docker compose` stacks *inside* workspaces, plan for 12–16 GB. It is a VM:
start at 8, watch `free -m`, bump if it swaps.

**Disk:** each Sysbox workspace keeps its inner Docker's images and layers
under `/var/lib/sysbox`, per workspace. That is what fills the disk, not the
workspace home dirs.

### Setup steps

1. ~~Create the VM~~ — **done 2026-09-27.** Built from the Ubuntu 24.04 cloud
   image (`noble-server-cloudimg-amd64.img`, kept in `/root/cloudimg/` on the
   Proxmox host) with cloud-init: user `ragib`, keys from
   `github.com/ragibkl.keys`, static IP, `ciupgrade` on. Same hardware settings
   as the k3s VMs (host CPU, VirtIO SCSI single, iothread, discard, NIC
   firewall, start at boot), plus `balloon: 0` and a serial console
   (cloud images expect one). qemu-guest-agent installed.
2. Base setup, mirroring `alpine-common`:
   - packages: `curl git jq wget qemu-guest-agent chrony` (`jq` is required
     by the Sysbox installer)
   - SSH keys from GitHub: reuse `alpine-common/github-keys.sh` and
     `sshd_config_common.conf` (`AuthorizedKeysCommand`). Both are plain sh,
     so they should work as is, but test before closing the console
   - Docker log rotation: reuse `alpine-common/daemon.json`
   - add `ragibkl` to `ssh-users/vmbr1.txt` if not there (it is, as of 2026-09-27)
3. Install Docker from **Docker's apt repo** — not the snap (Sysbox does not
   support snap Docker) and not Ubuntu's `docker.io` if avoidable.
4. Install Sysbox CE v0.7.1+ from the `.deb` on the GitHub release. **Stop and
   remove all containers first** — the installer restarts Docker. Verify
   `docker info | grep -i runtime` lists `sysbox-runc`.
5. Coder: `ubuntu-coder/docker-compose.yaml` with `coder` + `postgres`.
   - mount `/var/run/docker.sock` and add the docker group GID so Coder can
     create workspace containers
   - `CODER_ACCESS_URL=https://coder.vmbr1.ingress.ragib.dev`
   - port 7080 (or 3000) exposed to vmbr1
6. Workspace template: Coder's Docker template, with `runtime = "sysbox-runc"`
   on the `docker_container` resource. The workspace image needs systemd +
   dockerd (e.g. `nestybox/ubuntu-noble-systemd-docker`, or build one from it).
7. Ingress in the k3s cluster (`flux-deploy`,
   `clusters/vmbr1-k3s/services/local-proxy/`): ExternalName Service pointing
   at the VM + Ingress, same pattern as the old `jellyfin-proxy.yaml` (in git
   history). Add long websocket timeouts:
   `nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"` and
   `proxy-send-timeout: "3600"`.

### Decisions still open

- ~~Domain~~ — **`coder.vmbr1.ingress.ragib.dev`** (decided 2026-09-27).
  `*.vmbr1.ingress.ragib.dev` is already a wildcard DNS record to the cluster,
  so no DNS change is needed.
- **Wildcard app URLs** (`CODER_WILDCARD_ACCESS_URL=*.coder.<domain>`) to open
  workspace dev servers/ports in the browser. DNS already resolves
  `*.coder.vmbr1.ingress.ragib.dev` (the wildcard covers nested names); what is
  missing is a wildcard cert — cert-manager in the cluster uses HTTP-01, which cannot
  issue wildcards, so this means adding a DNS-01 solver. Can skip at first.

### Gotchas

- **Do not put oauth2-proxy in front of Coder.** Workspace agents and the
  `coder` CLI connect back to the access URL with Coder tokens; an oauth2-proxy
  redirect breaks them. Use Coder's built-in GitHub OAuth: create the admin
  account first, then restrict/disable signups.
- Workspace agents must reach `CODER_ACCESS_URL`. Going out through the
  public hostname and back in via the ingress works; if hairpin NAT is a
  problem on vmbr1, point the agents at the VM's internal address instead.
- Turn on the hypervisor's start-at-boot for this VM (and make sure it is
  *off* for the powered-down alpine-jellyfin, 10.15.1.157).

## alpine-jellyfin: decommissioned 2026-09-27

Powered off; the cluster proxies for jellyfin.bancuh.net and
transmission.bancuh.net are removed. The 3.7 TB data disk (`/mnt/sdb1`, ~1 TB
used: `shared/`, including `media/`) is still attached and intact.

- [ ] Disable start-at-boot for the VM in the hypervisor
- [ ] Decide what to keep from `/mnt/sdb1/shared`, then delete the VM and disk
