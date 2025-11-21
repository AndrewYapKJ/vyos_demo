# VyOS SD-WAN Solution

Enterprise-grade Software-Defined Wide Area Network (SD-WAN) implementation using VyOS (open-source), providing secure IPsec tunneling between branch offices and centralized aggregator with BGP-based dynamic routing.

## 🌟 Features

- **🔐 Secure Tunneling**: IPsec/IKEv2 with AES-256 encryption
- **🔄 Dynamic Routing**: BGP-based path selection and failover
- **☁️ Cloud-Ready**: AWS EC2 deployment with Terraform automation
- **🖥️ Multi-Platform**: macOS (UTM), Windows (Hyper-V/VMware) support
- **📊 SD-WAN Intelligence**: Health checks and automatic path selection
- **🚀 Easy Deployment**: One-click AWS deployment with scripts
- **🔧 Production Ready**: Scalable to multiple branches

## 🏗️ Architecture

```
                    Internet Cloud
                         |
            ┌─────────────────────────────┐
            │     AWS EC2 Aggregator     │
            │    (VyOS - AS 65000)       │
            │    Public IP: Dynamic      │
            └─────────────┬───────────────┘
                          │ IPsec/BGP Tunnels
            ┌─────────────────────────────┐
            │       Branch Office        │
            │    (VyOS - AS 65001)       │
            │   Public IP: Dynamic       │
            └─────────────┬───────────────┘
                          │
            ┌─────────────────────────────┐
            │      Local Network         │
            │    192.168.200.0/24        │
            └─────────────────────────────┘
```

### Network Flow
- **Primary Path**: Direct Internet (weight 15)
- **Backup Path**: VPN Tunnel (weight 20, preferred)
- **Failover**: Automatic based on health checks
- **Encryption**: End-to-end IPsec tunnel protection

## 🚀 Quick Start

### Prerequisites
- AWS Account with EC2 permissions
- Terraform >= 1.0
- AWS CLI configured
- macOS with UTM or Windows with Hyper-V

### 1. Deploy AWS Aggregator (5 minutes)

```bash
# Clone repository
git clone <this-repo>
cd vyos_demo

# Create SSH key and deploy
aws ec2 create-key-pair --key-name vyos-key --query 'KeyMaterial' --output text > vyos-key.pem
chmod 400 vyos-key.pem

# Deploy infrastructure
./scripts/deploy-aws.sh test YOUR_BRANCH_PUBLIC_IP
```

### 2. Setup Branch Office (10 minutes)

#### macOS Branch (UTM)
```bash
# Download and install UTM
open https://mac.getutm.app

# Download VyOS ISO
open https://downloads.vyos.io/rolling/current/amd64/vyos-rolling-latest.iso

# Create VM and apply configuration
# Copy configs/vyos-branch-macos.conf to VM
```

#### Windows Branch (Hyper-V)
```powershell
# Enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Import VyOS and apply configs/vyos-aggregator-windows.conf
```

### 3. Test Connection (2 minutes)

```bash
# Validate complete setup
./validation/test-connectivity.sh <AGGREGATOR-IP> <BRANCH-IP> vyos-key.pem
```

**Expected Results:**
- ✅ IPsec tunnel established
- ✅ BGP neighbors connected  
- ✅ End-to-end ping successful
- ✅ Routes exchanged via BGP

## 📁 Project Structure

```
vyos_demo/
├── configs/                    # VyOS configuration files
│   ├── vyos-aggregator-aws.conf       # AWS EC2 aggregator
│   ├── vyos-branch-macos.conf          # macOS branch office
│   └── vyos-aggregator-windows.conf    # Windows production
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                        # AWS resources definition
│   ├── user-data.sh                   # EC2 initialization script
│   └── terraform.tfvars.example       # Configuration template
├── scripts/                    # Automation scripts
│   └── deploy-aws.sh                  # One-click AWS deployment
├── validation/                 # Testing and validation
│   └── test-connectivity.sh           # Comprehensive connectivity tests
├── docs/                      # Documentation
│   └── SETUP_GUIDE.md                # Detailed setup instructions
└── README.md                  # This file
```

## 🛠️ Deployment Options

### Test Environment (AWS EC2)
- **Instance**: t3.small (2 vCPU, 2GB RAM)
- **Cost**: ~$20/month
- **Use Case**: Development and testing
- **Setup Time**: 15 minutes

### Production Environment (Windows + Starlink)
- **Platform**: Windows Hyper-V or VMware
- **Cost**: Hardware only (VyOS is free)
- **Use Case**: Production branch aggregator
- **Setup Time**: 30 minutes

### Branch Offices
- **macOS**: UTM virtual machine
- **Windows**: Hyper-V or VMware
- **Linux**: Native installation or KVM
- **Hardware**: Minimum 1GB RAM, 8GB storage

## 🔧 Configuration

### Key Parameters

| Parameter | AWS Aggregator | Branch Office |
|-----------|---------------|---------------|
| **BGP AS** | 65000 | 65001+ |
| **VTI Network** | 10.255.10.1/30 | 10.255.10.2/30 |
| **LAN Network** | 192.168.100.0/24 | 192.168.200.0/24 |
| **IPsec Mode** | Initiate | Respond |
| **Encryption** | AES-256 + SHA-256 | AES-256 + SHA-256 |

### Pre-Shared Key
- **Default**: `TestPSK2025!` (change for production)
- **Production**: Use certificate-based authentication

### Web Management
- **AWS Aggregator**: `https://<public-ip>` (API key: APIKeyAWS2025!)
- **Branch Office**: `https://192.168.200.1` (API key: APIKeyMac2025!)

## 📊 Monitoring & Management

### Health Checks
- **Probe Interval**: 5 seconds
- **Failure Threshold**: 3 failed probes
- **Target**: Remote public IP address
- **Action**: Automatic path failover

### SD-WAN Path Selection
```bash
# View path status
show sdwan interfaces
show sdwan health-check

# Manual failover
set sdwan path-group PRIMARY interface eth0 weight 10
set sdwan path-group BACKUP interface vti10 weight 5
```

### BGP Monitoring
```bash
# Check BGP status
show bgp summary
show bgp neighbors 10.255.10.2

# View routes
show ip route bgp
show bgp ipv4 unicast
```

## 🔍 Troubleshooting

### Common Issues

#### IPsec Tunnel Down
```bash
# Check tunnel status
show vpn ipsec sa

# Debug mode
set vpn ipsec logging log-modes ike
show log vpn ipsec
```

#### BGP Not Establishing
```bash
# Verify VTI connectivity
ping 10.255.10.1  # From branch to aggregator
ping 10.255.10.2  # From aggregator to branch

# Check BGP config
show protocols bgp
```

#### No Internet Access
```bash
# Check NAT rules
show nat source rules

# Verify default route
show ip route 0.0.0.0/0
```

### Debug Commands

| Issue | Command | Expected Output |
|-------|---------|----------------|
| **Tunnel Status** | `show vpn ipsec sa` | "established" |
| **BGP Status** | `show bgp summary` | "Established" |
| **Route Count** | `show ip route | wc -l` | > 5 routes |
| **Interface Status** | `show interfaces` | All UP |

## 🌐 Scaling & Production

### Multi-Branch Setup
1. **Add VTI interfaces** for each branch (vti20, vti30, etc.)
2. **Configure unique BGP AS** numbers (65002, 65003, etc.)
3. **Update security groups** for additional public IPs
4. **Use automation** for branch configuration generation

### High Availability
- **Dual aggregators** with BGP ECMP
- **Multiple tunnel paths** per branch
- **Health check redundancy** across paths
- **Automatic failover** based on SLA metrics

### Enterprise Features
- **OSPF integration** for internal routing
- **QoS policies** for application prioritization
- **Deep packet inspection** with application awareness
- **Centralized policy management** via REST API

## 💰 Cost Analysis

### AWS Costs (Monthly)
- **EC2 t3.small**: $15-20
- **Elastic IP**: $3.65
- **Data Transfer**: Variable (typically $5-15)
- **Total**: ~$25-40/month

### Branch Costs (One-time)
- **Hardware**: $0 (repurpose existing) to $500 (new mini-PC)
- **Software**: $0 (VyOS is open-source)
- **Setup**: $0 (self-service) to $500 (professional)

### ROI Calculation
- **Traditional MPLS**: $300-800/month per site
- **VyOS SD-WAN**: $25-50/month per site
- **Savings**: 75-90% cost reduction
- **Payback Period**: 2-3 months

## 🤝 Contributing

We welcome contributions! Please see:
- [Issues](issues) for bug reports
- [Pull Requests](pulls) for code contributions
- [Discussions](discussions) for feature requests

### Development Setup
```bash
# Fork repository
git clone <your-fork>
cd vyos_demo

# Make changes and test
./validation/test-connectivity.sh

# Submit pull request
```

## 📝 License

This project is open-source under the [MIT License](LICENSE). VyOS itself is available under GNU GPL v2.

## 🆘 Support

### Community Support
- **GitHub Issues**: Bug reports and feature requests
- **VyOS Forums**: [forum.vyos.io](https://forum.vyos.io/)
- **Reddit**: [r/vyos](https://www.reddit.com/r/vyos/)

### Professional Support
- **VyOS Commercial**: [vyos.io/support](https://vyos.io/support)
- **AWS Support**: [aws.amazon.com/support](https://aws.amazon.com/support)
- **Consulting**: Available for enterprise deployments

---

## 🎯 Next Steps

1. **[Deploy AWS Aggregator](terraform/)** - Start with cloud infrastructure
2. **[Setup Branch Office](configs/)** - Configure local VyOS instance  
3. **[Run Validation Tests](validation/)** - Verify connectivity
4. **[Read Setup Guide](docs/SETUP_GUIDE.md)** - Detailed instructions
5. **[Scale to Production](docs/SETUP_GUIDE.md#production-deployment)** - Multi-branch deployment

**Questions?** Open an [issue](issues) or check our [documentation](docs/).

**Ready to deploy?** Run `./scripts/deploy-aws.sh` to get started! 🚀