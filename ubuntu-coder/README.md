# ubuntu-coder

Self-hosted [Coder](https://coder.com/) on `vmbr1-ubuntu-coder` (Proxmox VM
1031, `10.15.1.31`), served at https://coder.vmbr1.ingress.ragib.dev.

- Coder server + Postgres run from `docker-compose.yaml`.
- Workspaces are Docker containers on this VM, run with the
  [Sysbox](https://github.com/nestybox/sysbox) runtime so they can run their
  own Docker without `--privileged` (template: `templates/docker-sysbox/`).
- The public URL goes through the vmbr1 k3s cluster: an ExternalName Service
  and Ingress in `flux-deploy`, `clusters/vmbr1-k3s/services/local-proxy/coder-proxy.yaml`.
  No oauth2-proxy there on purpose: agents and the CLI use Coder's own tokens.

## VM

| | |
|---|---|
| Hostname | `vmbr1-ubuntu-coder` — keytree matches it against [server-keys](https://github.com/ragibkl/server-keys) (`vmbr1-*`), so the `vmbr1-` prefix matters |
| VMID | `1031`, following the ID→IP pattern of the k3s VMs (`1021` → `.21`) |
| IP | `10.15.1.31`, static via cloud-init (outside the dnsmasq DHCP range `.100–.200`) |
| CPU / RAM / disk | 4 vCPU (type `host`), 8 GB (no ballooning), 100 GB on `local-lvm` |

**Why Ubuntu:** Sysbox has no Alpine package; it supports Ubuntu, Debian and
Flatcar. Ubuntu 24.04 needs kernel 6.8+ and Sysbox 0.7.1+ (0.7.1 fixed Noble
mount failures). Check https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md
before changing either.

**RAM:** base ~0.7 GB (Ubuntu, dockerd, Sysbox) plus ~0.5–0.8 GB for Coder and
Postgres. Each Sysbox workspace adds ~0.2–0.3 GB (systemd, inner dockerd) and
~0.5 GB (VS Code server), then whatever runs in it — rust-analyzer 1–3 GB,
tsserver ~1 GB, builds spike beyond that. 8 GB is one heavy (Rust) or two light
workspaces at a time; `docker compose` stacks inside workspaces want 12–16 GB.
Watch `free -m` and grow the VM if it swaps.

**Swap:** 4 GB at `/swapfile`, swappiness 10 (`../ubuntu-common/setup-swap.sh`),
added 2026-10-02 after two global OOM kills in one day: the workspace container
had no memory limit and the VM had no swap, so a memory spike inside the
workspace (several chrome-devtools-mcp copies plus Chromium) took the whole VM
down to the OOM killer.

**Disk:** each workspace's inner Docker keeps its images and layers in its own
`coder-<id>-docker` volume. That is what fills the disk, not home dirs.

## Setup

On a VM built as in `../ubuntu-common/README.md`:

```shell
cd homelab-vm/ubuntu-common
sudo ./setup.sh
sudo ./install-sysbox.sh
sudo ./setup-swap.sh

cd ../ubuntu-coder
sed -e "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" \
    -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" \
    sample.env > .env
chmod 600 .env
docker compose up -d
```

### First user

Whoever reaches a fresh Coder first gets to create the admin account, so
create it **before** the ingress exists (or with the ingress removed):

```shell
umask 077
openssl rand -base64 24 | tr -d "/+=" > ~/coder-admin-password
docker compose exec -T coder coder login http://localhost:7080 \
  --first-user-username ragib \
  --first-user-email <email> \
  --first-user-full-name "Ragib Badaruddin" \
  --first-user-password "$(cat ~/coder-admin-password)" \
  --first-user-trial=false
```

Log in on the web, change the password, delete `~/coder-admin-password`.

### GitHub login

Uses our own GitHub OAuth app; Coder's built-in default app is disabled
(Coder the company administers that one). Sign-ups are off, so GitHub login
only works for accounts that already exist.

1. https://github.com/settings/applications/new
   - Homepage URL: `https://coder.vmbr1.ingress.ragib.dev`
   - Authorization callback URL, exactly:
     `https://coder.vmbr1.ingress.ragib.dev/api/v2/users/oauth2/github/callback`
     (anything that isn't a prefix of this, on the same scheme and host,
     fails at GitHub with "The redirect_uri is not associated with this
     application")
   - leave device flow off
2. Put the client ID and a generated client secret in `.env`
   (`CODER_OAUTH2_GITHUB_CLIENT_ID`, `CODER_OAUTH2_GITHUB_CLIENT_SECRET`),
   then `docker compose up -d`.
3. Switch the existing password account to GitHub: `/settings/security` →
   **Single Sign On** → GitHub, confirm with the current password. The
   section only offers this while the account is still a password login.
   Check with `docker compose exec coder coder users show <user> -o json`
   (`login_type`). Done for `ragibkl` on 2026-09-27.

### Template

The CLI inside the container is logged in as the admin after the step above:

```shell
docker compose cp templates/docker-sysbox coder:/tmp/docker-sysbox
docker compose exec -T coder coder templates push docker-sysbox \
  --directory /tmp/docker-sysbox --yes
```

The startup script ends by running any executables in
`~/.config/coder/startup.d/` (persistent home), so each user can start their
own things on workspace start without changing the template. Hooks must
background anything long-running and redirect its output. Example: the
vmbr2 kubectl tunnel, a loop around `ssh -N vmbr2-socks` (a `~/.ssh/config`
entry with `DynamicForward 127.0.0.1:1080` through both routers), started by
`~/.config/coder/startup.d/vmbr2-tunnel`.

Non-interactive `coder create` needs `--use-parameter-defaults`: the
JetBrains module adds an IDE-selection parameter that otherwise waits for a
prompt forever.

## Wildcard app URLs

`CODER_WILDCARD_ACCESS_URL=*.coder.vmbr1.ingress.ragib.dev` serves workspace
apps and forwarded ports on their own subdomains, e.g. port 3000 of workspace
`dev` (agent `main`) at `https://3000--main--dev--ragibkl.coder.vmbr1.ingress.ragib.dev`.

- **DNS** (ClouDNS): explicit `coder.vmbr1.ingress.ragib.dev` and
  `*.coder.vmbr1.ingress.ragib.dev` CNAMEs to `vmbr1.ingress.ragib.dev`.
  The `*.vmbr1.ingress.ragib.dev` wildcard no longer covers them: the
  `_acme-challenge.coder.vmbr1.ingress.ragib.dev` CNAME below makes
  `coder.vmbr1.ingress.ragib.dev` exist in the zone, and a DNS wildcard
  never answers for a name that exists or anything under it.
- **Cert**: `coder-wildcard-ingress` in flux-deploy
  (`services/local-proxy/coder-proxy.yaml`), issued by the `letsencrypt-dns`
  ClusterIssuer via acme-dns (DNS-01), with
  `_acme-challenge.coder.vmbr1.ingress.ragib.dev` CNAMEd to its acme-dns
  registration.

## Upgrading

- **Coder:** bump `CODER_VERSION` in `.env` (stable channel:
  https://github.com/coder/coder/releases/latest), then
  `docker compose pull && docker compose up -d`.
- **Sysbox:** bump the version and checksum in
  `../ubuntu-common/install-sysbox.sh`, stop everything
  (`docker compose down` and all workspaces), re-run it.

## Not done yet

- **Agents hairpin through the VPS.** Workspace agents reach Coder via the
  public URL (VPS → frp → cluster → VM) even though Coder is on the same VM.
  Fine for now; if latency matters, point agents at the VM directly.
