#!/bin/bash
# Quick Configuration Deployment Script
# Usage: ./deploy-configs.sh [bandwidth_mbps] [qos_enable]

AGGREGATOR_IP="18.141.25.25"
BRANCH_IP="47.129.38.229"
SSH_KEY="~/.ssh/vyos-demo-key.pem"
BANDWIDTH=${1:-100}
ENABLE_QOS=${2:-true}

echo "🚀 Deploying SD-WAN Configuration"
echo "================================="
echo "Aggregator: $AGGREGATOR_IP"
echo "Branch: $BRANCH_IP" 
echo "Bandwidth: ${BANDWIDTH}Mbps"
echo "QoS: $ENABLE_QOS"
echo ""

deploy_to_instance() {
    local ip=$1
    local name=$2
    
    echo "📡 Deploying to $name ($ip)..."
    
    # Copy configuration scripts
    scp -i $SSH_KEY scripts/configure-bandwidth.sh scripts/configure-qos.sh ec2-user@$ip:~/
    
    # Make scripts executable
    ssh -i $SSH_KEY ec2-user@$ip "chmod +x *.sh"
    
    # Apply bandwidth configuration
    echo "  🔧 Configuring bandwidth limits..."
    ssh -i $SSH_KEY ec2-user@$ip "sudo ./configure-bandwidth.sh $BANDWIDTH $BANDWIDTH"
    
    # Apply QoS if enabled
    if [ "$ENABLE_QOS" = "true" ]; then
        echo "  🎯 Configuring QoS policies..."
        ssh -i $SSH_KEY ec2-user@$ip "sudo ./configure-qos.sh $BANDWIDTH"
    fi
    
    echo "  ✅ $name configuration completed"
    echo ""
}

# Deploy to both instances
deploy_to_instance "$AGGREGATOR_IP" "Aggregator"
deploy_to_instance "$BRANCH_IP" "Branch"

echo "🎉 Configuration deployment completed!"
echo ""
echo "📊 To monitor traffic:"
echo "  ssh -i $SSH_KEY ec2-user@$AGGREGATOR_IP"
echo "  sudo watch -n 1 'tc -s class show dev eth0'"
echo ""
echo "🔧 To modify settings:"
echo "  Bandwidth: ./configure-bandwidth.sh [download_mbps] [upload_mbps]" 
echo "  QoS: ./configure-qos.sh [total_bandwidth_mbps]"
echo ""
echo "📈 Current IPsec tunnel status:"
ssh -i $SSH_KEY ec2-user@$AGGREGATOR_IP "sudo strongswan status" 2>/dev/null | head -3