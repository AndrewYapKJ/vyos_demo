#!/bin/bash
# Bandwidth Configuration Script for SD-WAN
# Usage: ./configure-bandwidth.sh [download_mbps] [upload_mbps]

set -e

# Default values
DOWNLOAD_MBPS=${1:-100}
UPLOAD_MBPS=${2:-100}
INTERFACE="eth0"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

echo "🚀 SD-WAN Bandwidth Configuration"
echo "================================="
echo "Interface: $INTERFACE"
echo "Download Limit: ${DOWNLOAD_MBPS}Mbps"
echo "Upload Limit: ${UPLOAD_MBPS}Mbps"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root or with sudo"
    exit 1
fi

# Check if tc is available
if ! command -v tc &> /dev/null; then
    print_warning "Installing traffic control tools..."
    dnf install -y iproute-tc
fi

# Clear existing rules
print_status "Clearing existing traffic control rules..."
tc qdisc del dev $INTERFACE root 2>/dev/null || true
tc qdisc del dev $INTERFACE ingress 2>/dev/null || true

# Configure egress (upload) shaping
print_status "Configuring upload bandwidth limit: ${UPLOAD_MBPS}Mbps"
tc qdisc add dev $INTERFACE root handle 1: htb default 999
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${UPLOAD_MBPS}mbit
tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate ${UPLOAD_MBPS}mbit ceil ${UPLOAD_MBPS}mbit
tc class add dev $INTERFACE parent 1:1 classid 1:999 htb rate 1kbit ceil ${UPLOAD_MBPS}mbit

# Add fair queuing
tc qdisc add dev $INTERFACE parent 1:10 handle 10: fq_codel
tc qdisc add dev $INTERFACE parent 1:999 handle 999: fq_codel

# Configure ingress (download) shaping using IFB
print_status "Configuring download bandwidth limit: ${DOWNLOAD_MBPS}Mbps"

# Load IFB module if not loaded
modprobe ifb numifbs=1 2>/dev/null || true
ip link set dev ifb0 up 2>/dev/null || true

# Redirect ingress to IFB device
tc qdisc add dev $INTERFACE handle ffff: ingress
tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0

# Shape on IFB device
tc qdisc add dev ifb0 root handle 1: htb default 999
tc class add dev ifb0 parent 1: classid 1:1 htb rate ${DOWNLOAD_MBPS}mbit
tc class add dev ifb0 parent 1:1 classid 1:10 htb rate ${DOWNLOAD_MBPS}mbit ceil ${DOWNLOAD_MBPS}mbit
tc qdisc add dev ifb0 parent 1:10 handle 10: fq_codel

print_status "Bandwidth configuration applied successfully!"

# Show current configuration
echo ""
echo "📊 Current Traffic Control Configuration:"
echo "========================================"
echo "Egress (Upload) - $INTERFACE:"
tc qdisc show dev $INTERFACE
tc class show dev $INTERFACE

echo ""
echo "Ingress (Download) - ifb0:"
tc qdisc show dev ifb0 2>/dev/null || echo "No download shaping configured"
tc class show dev ifb0 2>/dev/null || true

echo ""
print_status "Bandwidth limits configured:"
echo "  Upload: ${UPLOAD_MBPS}Mbps"
echo "  Download: ${DOWNLOAD_MBPS}Mbps"
echo ""
echo "💡 To monitor usage: watch -n 1 'tc -s qdisc show dev $INTERFACE'"
echo "💡 To remove limits: tc qdisc del dev $INTERFACE root"
