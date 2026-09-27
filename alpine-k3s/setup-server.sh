#!/bin/sh
set -e

# Shared root mount, as on the workers (setup-longhorn.sh). node-exporter
# mounts / with HostToContainer propagation and fails to start without it.
mount --make-rshared /
if [ ! -f /etc/local.d/shared-mounts.start ]; then
    printf '#!/bin/sh\nmount --make-rshared /\n' > /etc/local.d/shared-mounts.start
    chmod +x /etc/local.d/shared-mounts.start
fi
rc-update add local

curl -sfL https://get.k3s.io | sh -s - server \
    --disable traefik \
    --disable local-storage \
    --node-taint CriticalAddonsOnly=true:NoExecute

echo K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
