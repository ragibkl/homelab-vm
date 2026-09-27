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

## Setup

On a VM built as in `../ubuntu-common/README.md`:

```shell
cd homelab-vm/ubuntu-common
sudo ./setup.sh
sudo ./install-sysbox.sh

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

### Template

The CLI inside the container is logged in as the admin after the step above:

```shell
docker compose cp templates/docker-sysbox coder:/tmp/docker-sysbox
docker compose exec -T coder coder templates push docker-sysbox \
  --directory /tmp/docker-sysbox --yes
```

Non-interactive `coder create` needs `--use-parameter-defaults`: the
JetBrains module adds an IDE-selection parameter that otherwise waits for a
prompt forever.

## Upgrading

- **Coder:** bump `CODER_VERSION` in `.env` (stable channel:
  https://github.com/coder/coder/releases/latest), then
  `docker compose pull && docker compose up -d`.
- **Sysbox:** bump the version and checksum in
  `../ubuntu-common/install-sysbox.sh`, stop everything
  (`docker compose down` and all workspaces), re-run it.

## Not done yet

- **Wildcard app URLs** (`CODER_WILDCARD_ACCESS_URL=*.coder.vmbr1.ingress.ragib.dev`).
  DNS already resolves the wildcard; the cert needs cert-manager DNS-01
  (the cluster issuer is HTTP-01 only). Until then, workspace apps are served
  path-based under the access URL.
- **Agents hairpin through the VPS.** Workspace agents reach Coder via the
  public URL (VPS → frp → cluster → VM) even though Coder is on the same VM.
  Fine for now; if latency matters, point agents at the VM directly.
