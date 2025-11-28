#!/bin/sh
set -e

echo "=== Alpine Router VM Setup ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Enable IP forwarding permanently
echo "Enabling IP forwarding..."
cat >> /etc/sysctl.conf << 'EOF'

# Enable IP forwarding for router functionality
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF

sysctl -p

# Configure network interfaces
echo "Network interfaces detected:"
ip -o link show | awk -F': ' '{print "  " $2}'
echo ""

cat << 'EOF'
Please configure /etc/network/interfaces manually:"
  eth0 = WAN (connected to vmbr0, DHCP from home network)"
  eth1 = LAN (connected to vmbr1, static 192.168.100.1/24)"

Example config:

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
    address 192.168.100.1
    netmask 255.255.255.0
EOF

# Configure SSH
echo "Configuring SSH..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

cat >> /etc/ssh/sshd_config << 'EOF'

# Fetch keys from GitHub
AuthorizedKeysCommand /usr/local/bin/github-keys.sh
AuthorizedKeysCommandUser root
EOF

# Configure SSH
echo "Configuring SSH for ProxyJump support..."
cp ./sshd_config_router.conf /etc/ssh/sshd_config.d/01_router.conf

# Enable and restart SSH
rc-update add sshd boot
rc-service sshd restart
