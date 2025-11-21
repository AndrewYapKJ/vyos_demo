#!/bin/bash
# QoS Configuration Script for SD-WAN
# Usage: ./configure-qos.sh [total_bandwidth_mbps]

set -e

# Configuration
TOTAL_BW=${1:-100}
INTERFACE="eth0"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

echo "🎯 SD-WAN QoS Configuration"
echo "==========================="
echo "Interface: $INTERFACE"
echo "Total Bandwidth: ${TOTAL_BW}Mbps"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root or with sudo"
    exit 1
fi

# Install required packages
if ! command -v tc &> /dev/null; then
    print_info "Installing traffic control tools..."
    dnf install -y iproute-tc iptables
fi

print_info "Clearing existing QoS configuration..."
# Clear existing configuration
tc qdisc del dev $INTERFACE root 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true

print_info "Setting up QoS class hierarchy..."
# Create root qdisc with HTB (Hierarchical Token Bucket)
tc qdisc add dev $INTERFACE root handle 1: htb default 40

# Create main class
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${TOTAL_BW}mbit

# Calculate bandwidth allocation (percentages of total)
VOICE_BW=$((TOTAL_BW * 20 / 100))      # 20% for voice/video
BUSINESS_BW=$((TOTAL_BW * 40 / 100))   # 40% for business apps  
WEB_BW=$((TOTAL_BW * 25 / 100))        # 25% for web browsing
BULK_BW=$((TOTAL_BW * 15 / 100))       # 15% for bulk data

print_info "Bandwidth allocation:"
echo "  Voice/Video: ${VOICE_BW}Mbps (20%)"
echo "  Business Apps: ${BUSINESS_BW}Mbps (40%)"
echo "  Web Browsing: ${WEB_BW}Mbps (25%)"
echo "  Bulk Data: ${BULK_BW}Mbps (15%)"
echo ""

# High priority class (Voice, Video calls) - Class 1:10
tc class add dev $INTERFACE parent 1:1 classid 1:10 htb \
    rate ${VOICE_BW}mbit ceil ${TOTAL_BW}mbit prio 1

# Medium-High priority class (Business applications) - Class 1:20  
tc class add dev $INTERFACE parent 1:1 classid 1:20 htb \
    rate ${BUSINESS_BW}mbit ceil ${TOTAL_BW}mbit prio 2

# Medium priority class (Web browsing) - Class 1:30
tc class add dev $INTERFACE parent 1:1 classid 1:30 htb \
    rate ${WEB_BW}mbit ceil ${TOTAL_BW}mbit prio 3

# Low priority class (Bulk data) - Class 1:40
tc class add dev $INTERFACE parent 1:1 classid 1:40 htb \
    rate ${BULK_BW}mbit ceil ${TOTAL_BW}mbit prio 4

print_info "Adding queue disciplines for each class..."
# Add fair queuing to each class
tc qdisc add dev $INTERFACE parent 1:10 handle 10: fq_codel
tc qdisc add dev $INTERFACE parent 1:20 handle 20: fq_codel  
tc qdisc add dev $INTERFACE parent 1:30 handle 30: fq_codel
tc qdisc add dev $INTERFACE parent 1:40 handle 40: fq_codel

print_info "Configuring traffic classification rules..."

# DSCP-based classification (if packets already marked)
tc filter add dev $INTERFACE parent 1:0 protocol ip prio 1 u32 \
    match ip dscp 0x2e 0xff flowid 1:10  # EF (Expedited Forwarding) -> Voice

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 2 u32 \
    match ip dscp 0x22 0xff flowid 1:20  # AF31 (Assured Forwarding) -> Business

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 3 u32 \
    match ip dscp 0x12 0xff flowid 1:30  # AF21 -> Web

# Port-based classification for common applications

# Voice traffic (SIP, RTP)
tc filter add dev $INTERFACE parent 1:0 protocol ip prio 1 u32 \
    match ip dport 5060 0xffff flowid 1:10  # SIP signaling

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 1 u32 \
    match ip dport 5061 0xffff flowid 1:10  # SIP TLS

# RTP range (common voice/video ports)
for port in $(seq 10000 10100); do
    tc filter add dev $INTERFACE parent 1:0 protocol ip prio 1 u32 \
        match ip dport $port 0xffff flowid 1:10 2>/dev/null || break
done

# Business applications  
tc filter add dev $INTERFACE parent 1:0 protocol ip prio 2 u32 \
    match ip dport 443 0xffff flowid 1:20   # HTTPS

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 2 u32 \
    match ip dport 22 0xffff flowid 1:20    # SSH

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 2 u32 \
    match ip dport 993 0xffff flowid 1:20   # IMAPS

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 2 u32 \
    match ip dport 995 0xffff flowid 1:20   # POP3S

# Web browsing
tc filter add dev $INTERFACE parent 1:0 protocol ip prio 3 u32 \
    match ip dport 80 0xffff flowid 1:30    # HTTP

tc filter add dev $INTERFACE parent 1:0 protocol ip prio 3 u32 \
    match ip dport 8080 0xffff flowid 1:30  # Alternative HTTP

# DNS (important for all traffic)
tc filter add dev $INTERFACE parent 1:0 protocol ip prio 2 u32 \
    match ip dport 53 0xffff flowid 1:20    # DNS

print_status "QoS configuration completed successfully!"

# Display current configuration
echo ""
echo "📊 Current QoS Configuration:"
echo "=============================="
tc -s qdisc show dev $INTERFACE
echo ""
echo "📋 Traffic Classes:"
tc -s class show dev $INTERFACE

echo ""
print_status "QoS Policy Summary:"
echo "  🎙️  Voice/Video (Class 1:10): ${VOICE_BW}Mbps, Priority 1"
echo "  💼 Business Apps (Class 1:20): ${BUSINESS_BW}Mbps, Priority 2"  
echo "  🌐 Web Browsing (Class 1:30): ${WEB_BW}Mbps, Priority 3"
echo "  📦 Bulk Data (Class 1:40): ${BULK_BW}Mbps, Priority 4"
echo ""
echo "💡 Monitor with: watch -n 1 'tc -s class show dev $INTERFACE'"
echo "💡 Remove QoS: tc qdisc del dev $INTERFACE root"
