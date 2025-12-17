#!/bin/sh
set -e

echo "=== Alpine Common VM Setup ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Update system
echo "Updating system..."
apk update
apk upgrade

# Install required packages
echo "Installing packages..."
apk add docker docker-compose curl openssh git wget qemu-guest-agent chrony

# Enable qemu-guest-agent
rc-update add qemu-guest-agent default || true
rc-service qemu-guest-agent start || true

# Enable and start Docker
echo "Enabling Docker..."
mkdir -p /etc/docker/
cp ./daemon.json /etc/docker/daemon.json

rc-update add docker boot
rc-service docker start

# Set up GitHub SSH keys with caching
echo "Setting up GitHub SSH key fetching..."
cp ./github-keys.sh /usr/local/bin/github-keys.sh

# Configure SSH
echo "Configuring SSH..."
cp ./sshd_config_common.conf /etc/ssh/sshd_config.d/00_common.conf

# Enable and restart SSH
rc-update add sshd boot
rc-service sshd restart

# Enable and restart chrony
rc-update add chronyd boot
rc-service chronyd start
