#!/bin/sh
set -e

echo "=== Alpine Router VM Setup ==="
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
apk add docker docker-compose curl openssh git

# Enable IP forwarding permanently
echo "Enabling IP forwarding..."
cat >> /etc/sysctl.conf << 'EOF'

# Enable IP forwarding for router functionality
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF

sysctl -p

# Enable and start Docker
echo "Enabling Docker..."
rc-update add docker boot
rc-service docker start

# Configure network interfaces
echo "Network interfaces detected:"
ip -o link show | awk -F': ' '{print "  " $2}'
echo ""
echo "Please configure /etc/network/interfaces manually:"
echo "  eth0 = WAN (connected to vmbr0, DHCP from home network)"
echo "  eth1 = LAN (connected to vmbr1, static 192.168.100.1/24)"
echo ""
echo "Example config:"
cat << 'EOF'

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
    address 192.168.100.1
    netmask 255.255.255.0

EOF

# Set up GitHub SSH keys with caching
echo "Setting up GitHub SSH key fetching..."
cat > /usr/local/bin/github-keys.sh << 'SCRIPT'
#!/bin/sh
GITHUB_USERNAME="ragibkl"
CACHE_FILE="/var/cache/github-keys.txt"
CACHE_DURATION=3600

mkdir -p "$(dirname "$CACHE_FILE")"

if [ -f "$CACHE_FILE" ]; then
    CURRENT_TIME=$(date +%s)
    FILE_TIME=$(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0)
    CACHE_AGE=$((CURRENT_TIME - FILE_TIME))
    
    if [ "$CACHE_AGE" -lt "$CACHE_DURATION" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

KEYS=$(curl -sf --max-time 5 "https://github.com/${GITHUB_USERNAME}.keys")

if [ $? -eq 0 ] && [ -n "$KEYS" ]; then
    echo "$KEYS" > "$CACHE_FILE"
    chmod 600 "$CACHE_FILE"
    echo "$KEYS"
else
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        cat /root/.ssh/authorized_keys 2>/dev/null || true
    fi
fi
SCRIPT

chmod +x /usr/local/bin/github-keys.sh

# Configure SSH
echo "Configuring SSH..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

cat >> /etc/ssh/sshd_config << 'EOF'

# Fetch keys from GitHub
AuthorizedKeysCommand /usr/local/bin/github-keys.sh
AuthorizedKeysCommandUser root
EOF

# Configure SSH (add after the existing SSH config section)
echo "Configuring SSH for ProxyJump support..."
cat >> /etc/ssh/sshd_config << 'EOF'

# Enable forwarding for ProxyJump
AllowTcpForwarding yes
PermitOpen any
EOF

# Enable and restart SSH
rc-update add sshd boot
rc-service sshd restart

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Edit /etc/network/interfaces to configure eth1"
echo "2. Reboot: reboot"
echo "3. After reboot, run: docker-compose up -d"
echo ""
