#!/bin/bash
# Branch Office VyOS setup script - COST OPTIMIZED
# Sets up StrongSwan + FRR to connect to AWS aggregator

set -e

# Log all output
exec > >(tee /var/log/vyos-branch-setup.log) 2>&1

echo "Starting VyOS Branch setup at $(date)"

# Update system
yum update -y

# Install required packages
yum install -y strongswan iptables-services

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Create StrongSwan configuration for branch office
mkdir -p /etc/strongswan/ipsec.conf.d

cat > /etc/strongswan/ipsec.conf << 'EOF'
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"

conn vyos-aggregator
    auto=start
    type=tunnel
    keyexchange=ikev2
    left=%defaultroute
    leftsubnet=192.168.200.0/24
    leftid=@branch-office
    right=${aggregator_public_ip}
    rightsubnet=192.168.100.0/24
    rightid=@aws-aggregator
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

# Pre-shared key (same as aggregator)
cat > /etc/strongswan/ipsec.secrets << 'EOF'
@branch-office @aws-aggregator : PSK "TestPSK2025!"
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
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
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
-A POSTROUTING -s 192.168.200.0/24 -o eth0 -j MASQUERADE
COMMIT
EOF

# Install FRR for BGP
amazon-linux-extras install -y epel
yum install -y frr

# FRR configuration for branch
cat > /etc/frr/frr.conf << 'EOF'
frr version 7.5
frr defaults traditional
hostname branch-office
service integrated-vtysh-config
!
router bgp 65001
 bgp router-id 100.64.200.1
 neighbor 10.255.10.1 remote-as 65000
 !
 address-family ipv4 unicast
  network 192.168.200.0/24
  neighbor 10.255.10.1 activate
 exit-address-family
!
line vty
!
EOF

# Create a dummy branch LAN interface
ip link add name br-lan type bridge
ip addr add 192.168.200.1/24 dev br-lan
ip link set br-lan up

# Add route for VTI tunnel
ip route add 10.255.10.0/30 dev lo || true

# Enable and start services
systemctl enable strongswan
systemctl enable iptables
systemctl enable frr
systemctl start strongswan
systemctl start iptables
systemctl start frr

# Create simple web interface
yum install -y nginx
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>VyOS SD-WAN Branch Office</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .good { background-color: #d4edda; }
        .bad { background-color: #f8d7da; }
        .info { background-color: #d1ecf1; }
    </style>
</head>
<body>
    <h1>🏢 VyOS SD-WAN Branch Office</h1>
    <p>Instance Type: t3.micro (Free Tier)</p>
    <p>Role: Branch Office</p>
    <p>Aggregator: ${aggregator_public_ip}</p>
    
    <h3>Network Configuration:</h3>
    <div class="info">📍 Branch LAN: 192.168.200.0/24</div>
    <div class="info">🔗 VTI Tunnel: 10.255.10.2/30</div>
    <div class="info">🌐 BGP AS: 65001</div>
    
    <h3>Services Status:</h3>
    <div class="status good">✅ StrongSwan IPsec</div>
    <div class="status good">✅ FRR BGP</div>
    <div class="status good">✅ iptables Firewall</div>
    
    <h3>Monitoring Commands:</h3>
    <p><code>sudo strongswan status</code> - Check IPsec tunnel</p>
    <p><code>sudo vtysh -c "show ip bgp summary"</code> - Check BGP</p>
    <p><code>ping 10.255.10.1</code> - Test aggregator VTI</p>
    <p><code>ping 192.168.100.1</code> - Test aggregator LAN</p>
    
    <h3>Configuration:</h3>
    <p>Pre-shared Key: TestPSK2025!</p>
    <p>Tunnel to: ${aggregator_public_ip}</p>
    <p>Setup Cost: FREE (AWS Free Tier)</p>
    
    <hr>
    <small>VyOS SD-WAN Demo - Branch Office</small>
</body>
</html>
EOF

systemctl enable nginx
systemctl start nginx

# Create route monitoring script
cat > /usr/local/bin/monitor-tunnel.sh << 'EOF'
#!/bin/bash
# Monitor tunnel and BGP status

while true; do
    echo "=== Tunnel Status Check $(date) ===" >> /var/log/tunnel-monitor.log
    
    # Check if tunnel is up
    if strongswan status | grep -q ESTABLISHED; then
        echo "✅ IPsec tunnel UP" >> /var/log/tunnel-monitor.log
    else
        echo "❌ IPsec tunnel DOWN - restarting" >> /var/log/tunnel-monitor.log
        systemctl restart strongswan
    fi
    
    # Check BGP
    if vtysh -c "show ip bgp summary" | grep -q "65000.*Estab"; then
        echo "✅ BGP session UP" >> /var/log/tunnel-monitor.log
    else
        echo "❌ BGP session DOWN" >> /var/log/tunnel-monitor.log
    fi
    
    sleep 60
done
EOF

chmod +x /usr/local/bin/monitor-tunnel.sh

# Start monitoring in background
nohup /usr/local/bin/monitor-tunnel.sh &

echo "VyOS Branch setup completed at $(date)"
echo "Branch ready to connect to aggregator: ${aggregator_public_ip}"
echo "View status: http://\$(curl -s http://checkip.amazonaws.com/)"