#!/bin/sh
set -e

# Ubuntu counterpart of alpine-common/setup.sh. Reuses the OS-agnostic pieces
# from alpine-common: the GitHub SSH key fetcher, its sshd config, and the
# Docker log rotation config.
#
# Docker comes from Docker's own apt repo, not the snap (Sysbox does not
# support snap Docker) and not Ubuntu's docker.io.

echo "=== Ubuntu Common VM Setup ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

cd "$(dirname "$0")"
COMMON=../alpine-common

export DEBIAN_FRONTEND=noninteractive

# Update system
echo "Updating system..."
apt-get update -qq
apt-get upgrade -y -qq

# Install required packages
echo "Installing packages..."
apt-get install -y -qq ca-certificates curl git jq wget qemu-guest-agent cloud-guest-utils

# Enable qemu-guest-agent
systemctl enable --now qemu-guest-agent

# Install Docker from Docker's apt repo
echo "Installing Docker..."
if snap list docker >/dev/null 2>&1; then
    echo "Error: the Docker snap is installed. Remove it first: snap remove docker"
    exit 1
fi
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker log rotation
mkdir -p /etc/docker/
cp "$COMMON/daemon.json" /etc/docker/daemon.json
systemctl enable docker
systemctl restart docker

# Let the login user run docker without sudo (the cloud-init user, e.g. ragib)
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -aG docker "$SUDO_USER"
    echo "Added $SUDO_USER to the docker group (takes effect on next login)"
fi

# Set up GitHub SSH keys with caching
echo "Setting up GitHub SSH key fetching..."
install -m 0755 -o root -g root "$COMMON/github-keys.sh" /usr/local/bin/github-keys.sh

# Configure SSH
echo "Configuring SSH..."
cp "$COMMON/sshd_config_common.conf" /etc/ssh/sshd_config.d/00_common.conf
sshd -t
systemctl restart ssh

echo ""
echo "=== Done ==="
docker --version
docker compose version
