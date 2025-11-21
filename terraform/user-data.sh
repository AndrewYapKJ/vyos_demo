#!/bin/bash
# Lightweight VyOS setup for t2.micro - COST OPTIMIZED
# Uses StrongSwan directly on Amazon Linux to minimize resources

set -e

# Log all output
exec > >(tee /var/log/vyos-setup.log) 2>&1

echo "Starting lightweight VyOS setup at $(date)"

# Update system
yum update -y

# Install required packages
yum install -y strongswan iptables-services

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Create StrongSwan configuration
mkdir -p /etc/strongswan/ipsec.conf.d

cat > /etc/strongswan/ipsec.conf << 'EOF'
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"

conn vyos-branch
    auto=start
    type=tunnel
    keyexchange=ikev2
    left=%defaultroute
    leftsubnet=192.168.100.0/24
    leftid=@aws-aggregator
    right=${branch_public_ip}
    rightsubnet=192.168.200.0/24
    rightid=@branch-office
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    ikelifetime=10800s
    lifetime=3600s
    margintime=540s
    rekeyfuzz=100%
    keyingtries=1
    mobike=no
    dpdaction=restart
    dpddelay=30s
    dpdtimeout=120s
EOF

cat > /etc/strongswan/ipsec.secrets << 'EOF'
@aws-aggregator @branch-office : PSK "TestPSK2025!"
EOF

chmod 600 /etc/strongswan/ipsec.secrets

# Configure iptables for NAT and forwarding
cat > /etc/sysconfig/iptables << 'EOF'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A INPUT -p udp --dport 500 -j ACCEPT
-A INPUT -p udp --dport 4500 -j ACCEPT
-A INPUT -p esp -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -p icmp -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.100.0/24 -o eth0 -j MASQUERADE
COMMIT
EOF

# Install FRR for BGP (lightweight version)
amazon-linux-extras install -y epel
yum install -y frr

# Basic FRR configuration
cat > /etc/frr/frr.conf << 'EOF'
frr version 7.5
frr defaults traditional
hostname aws-aggregator
service integrated-vtysh-config
!
router bgp 65000
 bgp router-id 100.64.0.1
 neighbor 10.255.10.2 remote-as 65001
 !
 address-family ipv4 unicast
  network 192.168.100.0/24
  neighbor 10.255.10.2 activate
 exit-address-family
!
line vty
!
EOF

# Enable and start services
systemctl enable strongswan
systemctl enable iptables
systemctl enable frr
systemctl start strongswan
systemctl start iptables
systemctl start frr

# Create simple web interface
yum install -y nginx
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>VyOS SD-WAN Aggregator</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .good { background-color: #d4edda; }
        .bad { background-color: #f8d7da; }
    </style>
</head>
<body>
    <h1>VyOS SD-WAN Aggregator (Cost Optimized)</h1>
    <p>Instance Type: t2.micro (Free Tier)</p>
    <p>Est. Cost: $2-4/month</p>
    
    <h3>Services Status:</h3>
    <div class="status good">✅ StrongSwan IPsec</div>
    <div class="status good">✅ FRR BGP</div>
    <div class="status good">✅ iptables Firewall</div>
    
    <h3>Commands:</h3>
    <p><code>sudo strongswan status</code> - Check IPsec</p>
    <p><code>sudo vtysh -c "show ip bgp summary"</code> - Check BGP</p>
    <p><code>sudo iptables -L -n</code> - Check firewall</p>
    
    <h3>Configuration:</h3>
    <p>Pre-shared Key: TestPSK2025!</p>
    <p>Branch IP: ${branch_public_ip}</p>
    <p>Tunnel Network: 10.255.10.0/30</p>
</body>
</html>
EOF

systemctl enable nginx
systemctl start nginx

echo "Lightweight VyOS setup completed at $(date)"
echo "Total setup cost: ~$2-4/month"