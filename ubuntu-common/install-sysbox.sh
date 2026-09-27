#!/bin/sh
set -e

# Install Sysbox CE, so containers can run Docker and systemd without
# --privileged. Run after setup.sh (needs Docker and jq).
#
# Supported hosts: https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md
# Ubuntu 24.04 needs kernel 6.8+ and Sysbox 0.7.1+ (0.7.1 fixed Noble mount
# failures).
#
# To upgrade: bump the version and checksum from the release page
# (https://github.com/nestybox/sysbox/releases), stop all containers, re-run.

SYSBOX_VERSION=0.7.1
SYSBOX_SHA256=9d6d5484f980d0a17f86c492c1262015c2afb66280bdb97215b79fde6a0261c5

echo "=== Sysbox ${SYSBOX_VERSION} Install ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

if docker info 2>/dev/null | grep -q sysbox-runc && dpkg -s sysbox-ce 2>/dev/null | grep -q "^Version: ${SYSBOX_VERSION}"; then
    echo "Sysbox ${SYSBOX_VERSION} is already installed"
    exit 0
fi

# The installer restarts Docker, and Sysbox asks for no running containers
# while it does.
if [ -n "$(docker ps -q)" ]; then
    echo "Error: containers are running. Stop them first, e.g.:"
    echo "  docker compose -f ../ubuntu-coder/docker-compose.yaml down"
    exit 1
fi

DEB="sysbox-ce_${SYSBOX_VERSION}.linux_$(dpkg --print-architecture).deb"
URL="https://github.com/nestybox/sysbox/releases/download/v${SYSBOX_VERSION}/${DEB}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading ${DEB}..."
curl -fsSL -o "$TMP/$DEB" "$URL"
echo "${SYSBOX_SHA256}  $TMP/$DEB" | sha256sum -c -

echo "Installing..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$TMP/$DEB"

echo ""
echo "=== Done ==="
systemctl is-active sysbox
docker info --format '{{json .Runtimes}}' | jq -r 'keys[]'
