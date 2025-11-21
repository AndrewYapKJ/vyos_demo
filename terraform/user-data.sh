#!/bin/bash
# User data script for VyOS EC2 instance
# This script runs on first boot to configure VyOS

# Wait for the system to be ready
sleep 30

# Apply VyOS configuration
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper <<EOF
configure

# Interfaces
set interfaces ethernet eth0 address 'dhcp'
set interfaces ethernet eth0 description 'WAN-AWS-PUBLIC'
set interfaces loopback lo address '100.64.0.1/32'

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

# Dial OUT to Branch
set vpn ipsec site-to-site peer BRANCH authentication mode 'pre-shared-secret'
set vpn ipsec site-to-site peer BRANCH authentication pre-shared-secret 'TestPSK2025!'
set vpn ipsec site-to-site peer BRANCH connection-type 'initiate'
set vpn ipsec site-to-site peer BRANCH ike-group 'IKE-VTI'
set vpn ipsec site-to-site peer BRANCH local-address 'dhcp'
set vpn ipsec site-to-site peer BRANCH remote-address '${branch_public_ip}'
set vpn ipsec site-to-site peer BRANCH vti bind 'vti10'
set vpn ipsec site-to-site peer BRANCH vti esp-group 'ESP-VTI'

set interfaces vti vti10 address '10.255.10.1/30'
set interfaces vti vti10 description 'VTI-BRANCH'
set interfaces vti vti10 mtu '1380'

# SD-WAN
set sdwan interfaces vti vti10
set sdwan path-group BRANCH interface 'vti10' weight '20'
set sdwan health-check BRANCH target '${branch_public_ip}'
set sdwan health-check BRANCH probe-interval '5'

# BGP
set protocols bgp system-as '65000'
set protocols bgp neighbor 10.255.10.2 remote-as '65001'
set protocols bgp address-family ipv4-unicast network '192.168.100.0/24'

# NAT
set nat source rule 100 outbound-interface 'eth0'
set nat source rule 100 source address '192.168.100.0/24'
set nat source rule 100 translation address 'masquerade'

# Firewall
set firewall ipv4 forward filter rule 10 action 'accept'
set firewall ipv4 forward filter rule 10 state established 'enable'
set firewall ipv4 forward filter rule 10 state related 'enable'

# GUI
set service https listen-address '0.0.0.0'
set service https api keys key 1 secret 'APIKeyAWS2025!'

# System
set system host-name 'vyos-aggregator-aws'
set system time-zone 'UTC'

commit
save
EOF

# Log completion
echo "VyOS configuration applied at $(date)" >> /var/log/vyos-userdata.log