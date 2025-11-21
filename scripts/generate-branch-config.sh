#!/bin/bash
# Generate branch configuration for multiple sites
# Usage: ./generate-branch-config.sh <branch_number> <public_ip> <local_network>

set -e

BRANCH_NUM=${1:-1}
PUBLIC_IP=${2:-"203.0.113.50"}
LOCAL_NETWORK=${3:-"192.168.200.0/24"}
LOCAL_IP=$(echo "$LOCAL_NETWORK" | sed 's|/24|.1|' | sed 's|\.0\.|.200.|')

echo "Generating VyOS configuration for Branch ${BRANCH_NUM}..."

cat > "configs/vyos-branch-${BRANCH_NUM}.conf" << EOF
# ========================================
# VyOS Branch Office ${BRANCH_NUM}
# Connects to AWS Aggregator
# ========================================

# Interfaces
set interfaces ethernet eth0 address 'dhcp'
set interfaces ethernet eth0 description 'WAN-BRANCH${BRANCH_NUM}-PUBLIC'
set interfaces ethernet eth1 address '${LOCAL_IP}/24'
set interfaces ethernet eth1 description 'LAN-BRANCH${BRANCH_NUM}'
set interfaces loopback lo address '100.64.${BRANCH_NUM}.1/32'

# IPsec
set vpn ipsec esp-group ESP-VTI lifetime '3600'
set vpn ipsec esp-group ESP-VTI mode 'tunnel'
set vpn ipsec esp-group ESP-VTI pfs 'enable'
set vpn ipsec esp-group ESP-VTI proposal 1 encryption 'aes256'
set vpn ipsec esp-group ESP-VTI proposal 1 hash 'sha256'

set vpn ipsec ike-group IKE-VTI key-exchange 'ikev2'
set vpn ipsec ike-group IKE-VTI lifetime '10800'
set vpn ipsec ike-group IKE-VTI proposal 1 dh-group '14'
set vpn ipsec ike-group IKE-VTI proposal 1 encryption 'aes256'
set vpn ipsec ike-group IKE-VTI proposal 1 hash 'sha256'

set vpn ipsec ipsec-interfaces interface 'eth0'

# Accept from AWS Aggregator
set vpn ipsec site-to-site peer AWS authentication mode 'pre-shared-secret'
set vpn ipsec site-to-site peer AWS authentication pre-shared-secret 'BranchPSK2025!'
set vpn ipsec site-to-site peer AWS connection-type 'respond'
set vpn ipsec site-to-site peer AWS ike-group 'IKE-VTI'
set vpn ipsec site-to-site peer AWS local-address 'dhcp'
set vpn ipsec site-to-site peer AWS remote-address '0.0.0.0'
set vpn ipsec site-to-site peer AWS vti bind 'vti${BRANCH_NUM}0'
set vpn ipsec site-to-site peer AWS vti esp-group 'ESP-VTI'

set interfaces vti vti${BRANCH_NUM}0 address '10.255.${BRANCH_NUM}0.2/30'
set interfaces vti vti${BRANCH_NUM}0 mtu '1380'

# SD-WAN
set sdwan interfaces ethernet eth0
set sdwan interfaces vti vti${BRANCH_NUM}0
set sdwan path-group DIRECT interface 'eth0' weight '15'
set sdwan path-group AWS interface 'vti${BRANCH_NUM}0' weight '20'

# BGP
set protocols bgp system-as '6500${BRANCH_NUM}'
set protocols bgp neighbor 10.255.${BRANCH_NUM}0.1 remote-as '65000'
set protocols bgp address-family ipv4-unicast network '${LOCAL_NETWORK}'

# NAT
set nat source rule 100 outbound-interface 'eth0'
set nat source rule 100 source address '${LOCAL_NETWORK}'
set nat source rule 100 translation address 'masquerade'

# Firewall
set firewall ipv4 forward filter rule 10 action 'accept'
set firewall ipv4 forward filter rule 10 state established 'enable'
set firewall ipv4 forward filter rule 10 state related 'enable'

# GUI
set service https listen-address '${LOCAL_IP}'
set service https api keys key 1 secret 'APIKeyBranch${BRANCH_NUM}2025!'

# System
set system host-name 'vyos-branch-${BRANCH_NUM}'
set system time-zone 'UTC'

commit
save
EOF

echo "✅ Configuration generated: configs/vyos-branch-${BRANCH_NUM}.conf"
echo ""
echo "📋 Branch ${BRANCH_NUM} Details:"
echo "  Public IP: ${PUBLIC_IP}"
echo "  Local Network: ${LOCAL_NETWORK}"
echo "  Local Gateway: ${LOCAL_IP}"
echo "  VTI Address: 10.255.${BRANCH_NUM}0.2/30"
echo "  BGP AS: 6500${BRANCH_NUM}"
echo ""
echo "🔧 Next steps:"
echo "1. Update aggregator config with peer BRANCH${BRANCH_NUM} remote-address '${PUBLIC_IP}'"
echo "2. Add VTI interface vti${BRANCH_NUM}0 with address 10.255.${BRANCH_NUM}0.1/30"
echo "3. Configure BGP neighbor 10.255.${BRANCH_NUM}0.2 remote-as 6500${BRANCH_NUM}"