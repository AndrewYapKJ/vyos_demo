#!/bin/bash
# VyOS SD-WAN Deployment Script for AWS
# Usage: ./deploy-aws.sh [environment] [branch_public_ip]

set -e

ENVIRONMENT=${1:-test}
BRANCH_IP=${2:-203.0.113.50}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

echo "🚀 Deploying VyOS SD-WAN Aggregator to AWS..."
echo "Environment: $ENVIRONMENT"
echo "Branch Public IP: $BRANCH_IP"

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Aborting." >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting." >&2; exit 1; }

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

# Navigate to terraform directory
cd "$TERRAFORM_DIR"

# Check if tfvars file exists
if [ ! -f "terraform.tfvars" ]; then
    echo "📝 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    sed -i.bak "s/203.0.113.50/$BRANCH_IP/g" terraform.tfvars
    sed -i.bak "s/test/$ENVIRONMENT/g" terraform.tfvars
    echo "⚠️  Please edit terraform.tfvars with your specific values"
fi

# Check if SSH key exists
KEY_NAME=$(grep 'key_name' terraform.tfvars | cut -d'"' -f2)
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    echo "❌ SSH key pair '$KEY_NAME' not found in AWS."
    echo "Create it with: aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME.pem"
    exit 1
fi

echo "📦 Initializing Terraform..."
terraform init

echo "📋 Planning deployment..."
terraform plan -var="environment=$ENVIRONMENT" -var="branch_public_ip=$BRANCH_IP"

echo "🎯 Applying configuration..."
terraform apply -auto-approve -var="environment=$ENVIRONMENT" -var="branch_public_ip=$BRANCH_IP"

echo ""
echo "✅ Deployment complete!"
echo ""
terraform output

# Wait for instance to be ready
echo ""
echo "⏳ Waiting for VyOS instance to be ready..."
PUBLIC_IP=$(terraform output -raw vyos_public_ip)
echo "Testing SSH connectivity to $PUBLIC_IP..."

for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" vyos@"$PUBLIC_IP" "show version" >/dev/null 2>&1; then
        echo "✅ VyOS is ready!"
        break
    else
        echo "Attempt $i/30: VyOS not ready yet, waiting 10 seconds..."
        sleep 10
    fi
    
    if [ $i -eq 30 ]; then
        echo "❌ Timeout waiting for VyOS to be ready"
        exit 1
    fi
done

echo ""
echo "🌐 Access Information:"
echo "SSH: ssh -i $KEY_NAME.pem vyos@$PUBLIC_IP"
echo "Web GUI: https://$PUBLIC_IP (API key: APIKeyAWS2025!)"
echo ""
echo "🔧 Next steps:"
echo "1. Update the branch configuration with aggregator IP: $PUBLIC_IP"
echo "2. Test the IPsec tunnel: ssh -i $KEY_NAME.pem vyos@$PUBLIC_IP 'show vpn ipsec sa'"
echo "3. Verify BGP: ssh -i $KEY_NAME.pem vyos@$PUBLIC_IP 'show bgp summary'"