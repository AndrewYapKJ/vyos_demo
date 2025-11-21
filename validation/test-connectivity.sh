#!/bin/bash
# VyOS SD-WAN Validation Script
# Tests IPsec tunnels, BGP, and connectivity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGGREGATOR_IP=${1:-}
BRANCH_IP=${2:-}
SSH_KEY=${3:-vyos-key.pem}

if [ -z "$AGGREGATOR_IP" ] || [ -z "$BRANCH_IP" ]; then
    echo "Usage: $0 <aggregator_ip> <branch_ip> [ssh_key]"
    echo "Example: $0 54.251.123.456 203.0.113.50 vyos-key.pem"
    exit 1
fi

echo "🔍 Validating VyOS SD-WAN Setup..."
echo "Aggregator: $AGGREGATOR_IP"
echo "Branch: $BRANCH_IP"
echo "SSH Key: $SSH_KEY"

# Test functions
test_ssh() {
    local ip=$1
    local desc=$2
    echo "🔗 Testing SSH connectivity to $desc ($ip)..."
    
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" vyos@"$ip" "show version" >/dev/null 2>&1; then
        echo "✅ SSH to $desc successful"
        return 0
    else
        echo "❌ SSH to $desc failed"
        return 1
    fi
}

test_ipsec() {
    local ip=$1
    local desc=$2
    echo "🔐 Testing IPsec on $desc ($ip)..."
    
    local result
    result=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" vyos@"$ip" "show vpn ipsec sa" 2>/dev/null | grep -c "established" || echo "0")
    
    if [ "$result" -gt 0 ]; then
        echo "✅ IPsec tunnel established on $desc ($result tunnel(s))"
        ssh -i "$SSH_KEY" vyos@"$ip" "show vpn ipsec sa" | head -20
        return 0
    else
        echo "❌ No IPsec tunnels established on $desc"
        return 1
    fi
}

test_bgp() {
    local ip=$1
    local desc=$2
    echo "🔄 Testing BGP on $desc ($ip)..."
    
    local result
    result=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" vyos@"$ip" "show bgp summary" 2>/dev/null | grep -c "Established" || echo "0")
    
    if [ "$result" -gt 0 ]; then
        echo "✅ BGP sessions established on $desc ($result session(s))"
        ssh -i "$SSH_KEY" vyos@"$ip" "show bgp summary"
        return 0
    else
        echo "❌ No BGP sessions established on $desc"
        return 1
    fi
}

test_connectivity() {
    echo "🏓 Testing end-to-end connectivity..."
    
    # Test ping from aggregator to branch VTI
    echo "Testing ping from aggregator to branch VTI (10.255.10.2)..."
    if ssh -o ConnectTimeout=10 -i "$SSH_KEY" vyos@"$AGGREGATOR_IP" "ping 10.255.10.2 count 3" >/dev/null 2>&1; then
        echo "✅ Aggregator can ping branch VTI"
    else
        echo "❌ Aggregator cannot ping branch VTI"
    fi
    
    # Test ping from branch to aggregator VTI
    echo "Testing ping from branch to aggregator VTI (10.255.10.1)..."
    if ssh -o ConnectTimeout=10 -i "$SSH_KEY" vyos@"$BRANCH_IP" "ping 10.255.10.1 count 3" >/dev/null 2>&1; then
        echo "✅ Branch can ping aggregator VTI"
    else
        echo "❌ Branch cannot ping aggregator VTI"
    fi
}

# Run tests
echo ""
echo "🧪 Starting validation tests..."
echo "================================="

# SSH Tests
test_ssh "$AGGREGATOR_IP" "Aggregator"
AGG_SSH=$?
test_ssh "$BRANCH_IP" "Branch"
BRANCH_SSH=$?

if [ $AGG_SSH -eq 0 ] && [ $BRANCH_SSH -eq 0 ]; then
    echo ""
    echo "🔐 IPsec Tests"
    echo "=============="
    test_ipsec "$AGGREGATOR_IP" "Aggregator"
    test_ipsec "$BRANCH_IP" "Branch"
    
    echo ""
    echo "🔄 BGP Tests"
    echo "============"
    test_bgp "$AGGREGATOR_IP" "Aggregator"
    test_bgp "$BRANCH_IP" "Branch"
    
    echo ""
    echo "🏓 Connectivity Tests"
    echo "===================="
    test_connectivity
    
    echo ""
    echo "📊 Route Tables"
    echo "==============="
    echo "Aggregator routes:"
    ssh -i "$SSH_KEY" vyos@"$AGGREGATOR_IP" "show ip route" | head -10
    echo ""
    echo "Branch routes:"
    ssh -i "$SSH_KEY" vyos@"$BRANCH_IP" "show ip route" | head -10
else
    echo "❌ SSH connectivity failed, skipping other tests"
fi

echo ""
echo "🏁 Validation complete!"
echo ""
echo "📋 Summary:"
echo "- Aggregator SSH: $([ $AGG_SSH -eq 0 ] && echo "✅" || echo "❌")"
echo "- Branch SSH: $([ $BRANCH_SSH -eq 0 ] && echo "✅" || echo "❌")"
echo ""
echo "💡 Troubleshooting:"
echo "- Check security groups allow UDP 500, 4500 and protocol 50"
echo "- Verify public IPs are correct in configurations"
echo "- Check VyOS logs: sudo journalctl -u strongswan"