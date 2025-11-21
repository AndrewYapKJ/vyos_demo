#!/bin/bash
# Quick health check script for VyOS SD-WAN
# Usage: ./health-check.sh <vyos_ip> [ssh_key]

set -e

VYOS_IP=${1:-}
SSH_KEY=${2:-vyos-key.pem}

if [ -z "$VYOS_IP" ]; then
    echo "Usage: $0 <vyos_ip> [ssh_key]"
    echo "Example: $0 54.251.123.456 vyos-key.pem"
    exit 1
fi

echo "🩺 VyOS Health Check for $VYOS_IP"
echo "================================"

# Quick SSH test
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY" vyos@"$VYOS_IP" "exit" >/dev/null 2>&1; then
    echo "❌ Cannot connect via SSH"
    exit 1
fi

echo "✅ SSH connectivity OK"

# System status
echo ""
echo "📊 System Status:"
ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show version | head -3"
ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show system uptime"

# Interface status
echo ""
echo "🌐 Interface Status:"
ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show interfaces | grep -E '(eth0|vti|lo)'"

# IPsec status
echo ""
echo "🔐 IPsec Status:"
IPSEC_STATUS=$(ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show vpn ipsec sa" 2>/dev/null || echo "No tunnels")
if echo "$IPSEC_STATUS" | grep -q "established"; then
    echo "✅ IPsec tunnels active:"
    echo "$IPSEC_STATUS" | grep -E "(Tunnel|State|Remote)"
else
    echo "⚠️  No active IPsec tunnels"
fi

# BGP status
echo ""
echo "🔄 BGP Status:"
BGP_STATUS=$(ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show bgp summary" 2>/dev/null || echo "BGP not configured")
if echo "$BGP_STATUS" | grep -q "Established"; then
    echo "✅ BGP neighbors active:"
    echo "$BGP_STATUS" | grep -E "(Neighbor|State/PfxRcd)"
else
    echo "⚠️  No active BGP sessions"
fi

# Route count
echo ""
echo "🗺️  Route Summary:"
ROUTE_COUNT=$(ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show ip route | wc -l" 2>/dev/null || echo "0")
echo "Total routes: $ROUTE_COUNT"

# SD-WAN status (if configured)
echo ""
echo "📡 SD-WAN Status:"
SDWAN_STATUS=$(ssh -i "$SSH_KEY" vyos@"$VYOS_IP" "show sdwan interfaces" 2>/dev/null || echo "SD-WAN not configured")
if [ "$SDWAN_STATUS" != "SD-WAN not configured" ]; then
    echo "✅ SD-WAN configured:"
    echo "$SDWAN_STATUS"
else
    echo "⚠️  SD-WAN not configured or not available"
fi

echo ""
echo "🏁 Health check complete for $VYOS_IP"