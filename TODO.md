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

### Status

**Done 2026-09-27.** Coder v2.36.6 is running with a Sysbox workspace template,
at https://coder.vmbr1.ingress.ragib.dev. How it was built and how to rebuild
it: `ubuntu-common/README.md` (VM + base setup + Sysbox) and
`ubuntu-coder/README.md` (Coder, first user, template, upgrades).

Smoke-tested end to end: a workspace from `docker-sysbox` ran with
`runtime=sysbox-runc`, `privileged=false`, its agent connected through the
public URL, and `docker run hello-world` worked inside it.

### Still open

- **Wildcard app URLs** (`CODER_WILDCARD_ACCESS_URL=*.coder.<domain>`) to open
  workspace dev servers/ports in the browser. DNS already resolves
  `*.coder.vmbr1.ingress.ragib.dev` (the wildcard covers nested names); what is
  missing is a wildcard cert — cert-manager in the cluster uses HTTP-01, which cannot
  issue wildcards, so this means adding a DNS-01 solver. Can skip at first.

### Gotchas

- **Do not put oauth2-proxy in front of Coder.** Workspace agents and the
  `coder` CLI connect back to the access URL with Coder tokens; an oauth2-proxy
  redirect breaks them. Coder does its own login; only the admin can add users.
- Workspace agents must reach `CODER_ACCESS_URL`. Going out through the
  public hostname and back in via the ingress works; if hairpin NAT is a
  problem on vmbr1, point the agents at the VM's internal address instead.

## alpine-jellyfin: decommissioned 2026-09-27

Powered off; the cluster proxies for jellyfin.bancuh.net and
transmission.bancuh.net are removed. The 3.7 TB data disk (`/mnt/sdb1`, ~1 TB
used: `shared/`, including `media/`) is still attached and intact.

- [x] Disable start-at-boot for the VM in the hypervisor (VM 231, 2026-09-27)
- [ ] Decide what to keep from `/mnt/sdb1/shared`, then delete the VM and disk
