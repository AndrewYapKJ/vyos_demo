# VyOS SD-WAN Setup Guide

Comprehensive guide for deploying VyOS-based SD-WAN solution with IPsec tunnels and BGP routing.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Detailed Setup](#detailed-setup)
6. [Configuration](#configuration)
7. [Testing & Validation](#testing--validation)
8. [Troubleshooting](#troubleshooting)
9. [Production Deployment](#production-deployment)

## Overview

This project implements a Software-Defined Wide Area Network (SD-WAN) using VyOS (open-source) with the following components:

- **AWS EC2 Aggregator**: Centralized hub for branch connectivity
- **macOS Branch**: UTM-based VyOS for testing
- **Windows Production**: Hyper-V/VMware for production aggregator
- **Automated Deployment**: Terraform and shell scripts
- **Monitoring**: Health checks and BGP-based failover

## Architecture

```
Internet
    |
[AWS EC2 Aggregator] ←→ [macOS/Windows Branch]
    |                        |
[Corporate Network]      [Branch LAN]
    |                        |
192.168.100.0/24       192.168.200.0/24
```

### Network Design
- **Tunnel Network**: 10.255.10.0/30 (VTI interfaces)
- **BGP AS Numbers**: 65000 (Aggregator), 65001+ (Branches)
- **IPsec**: IKEv2 with AES-256 encryption
- **SD-WAN**: Path selection based on health checks

## Prerequisites

### Software Requirements
- **AWS Account** with EC2 access
- **Terraform** >= 1.0
- **AWS CLI** configured
- **SSH client**

### For Branch Office
- **macOS**: UTM (free virtualization)
- **Windows**: Hyper-V Pro or VMware Workstation
- **VyOS ISO**: Download from [vyos.io](https://vyos.io)

### Network Requirements
- **Public IP addresses** for both aggregator and branch
- **Firewall ports**: UDP 500, 4500, ESP (protocol 50)
- **Internet connectivity** with sufficient bandwidth

## Quick Start

### 1. Deploy AWS Aggregator

```bash
# Clone the repository
git clone <repository-url>
cd vyos_demo

# Configure AWS credentials
aws configure

# Create SSH key pair
aws ec2 create-key-pair --key-name vyos-key --query 'KeyMaterial' --output text > vyos-key.pem
chmod 400 vyos-key.pem

# Deploy to AWS
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your branch public IP

terraform init
terraform plan
terraform apply
```

### 2. Setup Branch Office

#### Option A: macOS with UTM
1. Download UTM from [mac.getutm.app](https://mac.getutm.app)
2. Download VyOS ISO from [vyos.io](https://vyos.io)
3. Create VM:
   - CPU: 2 cores
   - RAM: 2GB
   - Network: Bridged (to get public IP)
4. Install VyOS and apply branch configuration

#### Option B: Windows with Hyper-V
1. Enable Hyper-V: `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`
2. Create VM with VyOS ISO
3. Configure external network switch
4. Apply branch configuration

### 3. Configure and Test

```bash
# Update aggregator with branch public IP
ssh -i vyos-key.pem vyos@<AGGREGATOR-IP>
configure
set vpn ipsec site-to-site peer MACOS remote-address '<BRANCH-PUBLIC-IP>'
commit
save

# Test connectivity
./validation/test-connectivity.sh <AGGREGATOR-IP> <BRANCH-IP> vyos-key.pem
```

## Detailed Setup

### AWS Aggregator Configuration

The aggregator serves as the central hub:

**Key Features:**
- Elastic IP for consistent addressing
- Security groups for IPsec traffic
- Auto-configuration via user-data script
- BGP for dynamic routing

**Configuration highlights:**
```bash
# IPsec tunnel to branch
set vpn ipsec site-to-site peer BRANCH connection-type 'initiate'
set vpn ipsec site-to-site peer BRANCH remote-address '<BRANCH-IP>'

# BGP for route exchange
set protocols bgp system-as '65000'
set protocols bgp neighbor 10.255.10.2 remote-as '65001'

# SD-WAN health checking
set sdwan health-check BRANCH target '<BRANCH-IP>'
set sdwan health-check BRANCH probe-interval '5'
```

### Branch Office Configuration

The branch connects to the aggregator:

**Key Features:**
- Dual-WAN capability (Direct + VPN)
- Local LAN network
- BGP route advertisement
- SD-WAN path selection

**Configuration highlights:**
```bash
# Accept connections from aggregator
set vpn ipsec site-to-site peer AWS connection-type 'respond'
set vpn ipsec site-to-site peer AWS remote-address '0.0.0.0'

# Local network advertisement
set protocols bgp address-family ipv4-unicast network '192.168.200.0/24'

# SD-WAN with multiple paths
set sdwan path-group DIRECT interface 'eth0' weight '15'
set sdwan path-group VPN interface 'vti10' weight '20'
```

## Configuration Files

### AWS Aggregator
- **Location**: `configs/vyos-aggregator-aws.conf`
- **Purpose**: Centralized hub configuration
- **Features**: Multi-branch support, BGP, SD-WAN

### macOS Branch
- **Location**: `configs/vyos-branch-macos.conf`
- **Purpose**: Test branch configuration
- **Features**: UTM compatibility, dual-WAN

### Windows Production
- **Location**: `configs/vyos-aggregator-windows.conf`
- **Purpose**: Production aggregator with Starlink
- **Features**: Multiple branches, enhanced monitoring

## Testing & Validation

### Automated Testing

Run the comprehensive test suite:

```bash
./validation/test-connectivity.sh <AGGREGATOR-IP> <BRANCH-IP>
```

**Tests include:**
- SSH connectivity
- IPsec tunnel establishment
- BGP neighbor relationships
- End-to-end connectivity
- Route table validation

### Manual Verification

#### Check IPsec Status
```bash
show vpn ipsec sa
```

#### Verify BGP
```bash
show bgp summary
show bgp neighbors
```

#### Test Connectivity
```bash
ping 10.255.10.2  # From aggregator to branch VTI
ping 192.168.200.1  # From aggregator to branch LAN
```

#### SD-WAN Status
```bash
show sdwan interfaces
show sdwan health-check
```

## Troubleshooting

### Common Issues

#### 1. IPsec Tunnel Not Establishing
```bash
# Check IPsec logs
sudo journalctl -u strongswan

# Verify pre-shared key matches
show configuration commands | grep pre-shared-secret

# Check security groups/firewall
# Ensure UDP 500, 4500 and ESP (protocol 50) are allowed
```

#### 2. BGP Not Establishing
```bash
# Check BGP configuration
show bgp summary
show bgp neighbors

# Verify AS numbers match in tunnel configuration
# Check VTI interface status
show interfaces vti
```

#### 3. No Internet via Tunnel
```bash
# Check NAT rules
show nat source rules

# Verify routing
show ip route
traceroute 8.8.8.8
```

### Debug Commands

#### IPsec Debugging
```bash
# Enable debugging
set vpn ipsec logging log-modes ike
set vpn ipsec logging log-modes charon

# View logs
show log vpn ipsec
```

#### BGP Debugging
```bash
# Enable BGP debugging
set protocols bgp parameters log-neighbor-changes

# View BGP events
show log bgp
```

## Production Deployment

### Scaling to Multiple Branches

1. **Update Aggregator Configuration**:
```bash
# Add additional VTI interfaces
set interfaces vti vti20 address '10.255.20.1/30'
set interfaces vti vti30 address '10.255.30.1/30'

# Configure additional IPsec peers
set vpn ipsec site-to-site peer BRANCH2 remote-address '<BRANCH2-IP>'
set vpn ipsec site-to-site peer BRANCH3 remote-address '<BRANCH3-IP>'

# BGP neighbors
set protocols bgp neighbor 10.255.20.2 remote-as '65002'
set protocols bgp neighbor 10.255.30.2 remote-as '65003'
```

2. **Use Ansible for Automation**:
```bash
# Generate branch configurations
ansible-playbook deploy-branches.yml -e branch_count=10
```

### High Availability

#### AWS Aggregator HA
- Deploy in multiple AZ using Auto Scaling Groups
- Use Network Load Balancer for redundancy
- Implement BGP anycast addressing

#### Branch HA
- Configure dual-WAN (Direct Internet + VPN)
- Use SD-WAN policies for failover
- Implement backup tunnel paths

### Monitoring

#### CloudWatch Integration
- Custom metrics for tunnel status
- BGP neighbor state monitoring
- Network throughput alerts

#### VyOS Monitoring
```bash
# Built-in health checks
set sdwan health-check BRANCH target '8.8.8.8'
set sdwan health-check BRANCH probe-interval '5'
set sdwan health-check BRANCH failure-threshold '3'

# SNMP monitoring
set service snmp community public authorization 'ro'
set service snmp location 'Branch-Office'
```

## Security Considerations

### IPsec Security
- **Encryption**: AES-256 with SHA-256 HMAC
- **Key Exchange**: IKEv2 with DH Group 14
- **PFS**: Perfect Forward Secrecy enabled
- **Certificates**: Consider replacing PSK with certificates

### Network Security
- **Firewall Rules**: Restrictive by default
- **VTI Networks**: Isolated tunnel addressing
- **Management Access**: Restrict GUI/SSH access
- **Regular Updates**: Keep VyOS updated

### Best Practices
1. **Change default passwords** and API keys
2. **Use certificate-based authentication** for production
3. **Implement network segmentation** at branch offices
4. **Regular security audits** and penetration testing
5. **Monitor and log** all network traffic

## Cost Optimization

### AWS Costs
- **Instance Type**: t3.small sufficient for testing
- **Data Transfer**: Optimize for regional traffic
- **Elastic IP**: Single EIP per aggregator
- **Storage**: Minimal EBS volume requirements

### Branch Costs
- **Hardware**: Repurpose existing hardware
- **Internet**: Leverage existing connections
- **Licensing**: VyOS is open-source (no licensing costs)

## Support and Resources

### Documentation
- [VyOS Documentation](https://docs.vyos.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [StrongSwan IPsec](https://wiki.strongswan.org/)

### Community
- [VyOS Forums](https://forum.vyos.io/)
- [Reddit r/vyos](https://www.reddit.com/r/vyos/)
- [GitHub Issues](https://github.com/vyos/vyos-build/issues)

### Professional Support
- VyOS Professional Support: [vyos.io/support](https://vyos.io/support)
- AWS Support: [aws.amazon.com/support](https://aws.amazon.com/support)

---

**Note**: This is a comprehensive guide for educational and testing purposes. For production deployments, consider professional consultation and security audits.