#!/bin/bash
# Automated SD-WAN Deployment Script
# This script demonstrates the complete IaC deployment workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="test"
KEY_NAME="vyos-demo-key"
REGION="ap-southeast-1"

echo -e "${BLUE}🚀 VyOS SD-WAN Automated Deployment${NC}"
echo "======================================"
echo ""

# Function to print status messages
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        echo "Visit: https://terraform.io/downloads"
        exit 1
    fi
    print_status "Terraform found: $(terraform --version | head -1)"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        echo "Visit: https://aws.amazon.com/cli/"
        exit 1
    fi
    print_status "AWS CLI found: $(aws --version)"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    local aws_account=$(aws sts get-caller-identity --query Account --output text)
    print_status "AWS Account: $aws_account"
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/${KEY_NAME}.pem ]; then
        print_warning "SSH key not found. Creating new key pair..."
        create_ssh_key
    else
        print_status "SSH key found: ~/.ssh/${KEY_NAME}.pem"
    fi
}

# Function to create SSH key pair
create_ssh_key() {
    print_info "Creating SSH key pair: $KEY_NAME"
    
    # Check if key pair already exists in AWS
    if aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION &> /dev/null; then
        print_warning "Key pair $KEY_NAME already exists in AWS. Deleting..."
        aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION
    fi
    
    # Create new key pair
    aws ec2 create-key-pair \
        --key-name $KEY_NAME \
        --region $REGION \
        --query 'KeyMaterial' \
        --output text > ~/.ssh/${KEY_NAME}.pem
    
    chmod 400 ~/.ssh/${KEY_NAME}.pem
    print_status "SSH key pair created and saved to ~/.ssh/${KEY_NAME}.pem"
}

# Function to deploy aggregator
deploy_aggregator() {
    print_info "Deploying AWS Aggregator..."
    
    cd terraform/
    
    # Initialize Terraform
    print_info "Initializing Terraform..."
    terraform init -upgrade
    
    # Get user's public IP for temporary access
    local user_ip
    user_ip=$(curl -s https://ipinfo.io/ip 2>/dev/null || echo "0.0.0.0")
    print_info "Detected public IP: $user_ip"
    
    # Create terraform.tfvars with placeholder for branch IP
    cat > terraform.tfvars << EOF
environment = "$ENVIRONMENT"
branch_public_ip = "1.1.1.1"  # Placeholder - will be updated after branch deployment
instance_type = "t3.micro"
key_name = "$KEY_NAME"
EOF
    
    print_info "Running Terraform plan..."
    terraform plan -var="environment=$ENVIRONMENT" -var="branch_public_ip=1.1.1.1"
    
    print_info "Applying Terraform configuration..."
    terraform apply -auto-approve \
        -var="environment=$ENVIRONMENT" \
        -var="branch_public_ip=1.1.1.1"
    
    # Get aggregator public IP
    local aggregator_ip
    aggregator_ip=$(terraform output -raw aggregator_public_ip 2>/dev/null || echo "")
    
    if [ -z "$aggregator_ip" ]; then
        print_error "Failed to get aggregator public IP"
        exit 1
    fi
    
    print_status "Aggregator deployed successfully!"
    print_status "Aggregator Public IP: $aggregator_ip"
    
    # Save aggregator IP for branch deployment
    echo "$aggregator_ip" > ../aggregator_ip.txt
    
    cd ..
}

# Function to deploy branch
deploy_branch() {
    local aggregator_ip=$1
    
    print_info "Deploying Branch Office..."
    
    cd terraform/branch/
    
    # Initialize Terraform
    print_info "Initializing Branch Terraform..."
    terraform init -upgrade
    
    # Create terraform.tfvars
    cat > terraform.tfvars << EOF
environment = "$ENVIRONMENT"
aggregator_public_ip = "$aggregator_ip"
instance_type = "t3.micro"
key_name = "$KEY_NAME"
EOF
    
    print_info "Running Branch Terraform plan..."
    terraform plan
    
    print_info "Applying Branch Terraform configuration..."
    terraform apply -auto-approve
    
    # Get branch public IP
    local branch_ip
    branch_ip=$(terraform output -raw branch_public_ip 2>/dev/null || echo "")
    
    if [ -z "$branch_ip" ]; then
        print_error "Failed to get branch public IP"
        exit 1
    fi
    
    print_status "Branch deployed successfully!"
    print_status "Branch Public IP: $branch_ip"
    
    # Save branch IP
    echo "$branch_ip" > ../../branch_ip.txt
    
    cd ../..
    
    # Update aggregator configuration with actual branch IP
    update_aggregator_config "$branch_ip"
}

# Function to update aggregator with branch IP
update_aggregator_config() {
    local branch_ip=$1
    
    print_info "Updating aggregator configuration with branch IP: $branch_ip"
    
    cd terraform/
    
    # Update terraform.tfvars with actual branch IP
    sed -i.bak "s/branch_public_ip = \"1.1.1.1\"/branch_public_ip = \"$branch_ip\"/" terraform.tfvars
    
    print_info "Applying updated configuration..."
    terraform apply -auto-approve \
        -var="environment=$ENVIRONMENT" \
        -var="branch_public_ip=$branch_ip"
    
    cd ..
}

# Function to wait for instances to be ready
wait_for_instances() {
    local aggregator_ip=$1
    local branch_ip=$2
    
    print_info "Waiting for instances to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_info "Attempt $attempt/$max_attempts - Testing SSH connectivity..."
        
        # Test aggregator
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem ec2-user@$aggregator_ip "exit" &> /dev/null; then
            print_status "Aggregator SSH ready"
            aggregator_ready=true
        else
            aggregator_ready=false
        fi
        
        # Test branch
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem ec2-user@$branch_ip "exit" &> /dev/null; then
            print_status "Branch SSH ready"
            branch_ready=true
        else
            branch_ready=false
        fi
        
        if [ "$aggregator_ready" = true ] && [ "$branch_ready" = true ]; then
            print_status "Both instances are ready!"
            break
        fi
        
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "Instances did not become ready within expected time"
        exit 1
    fi
}

# Function to run health check
run_health_check() {
    local aggregator_ip=$1
    local branch_ip=$2
    
    print_info "Running comprehensive health check..."
    
    # Make sure health check script is executable
    chmod +x scripts/strongswan-health-check.sh
    
    # Run health check
    if ./scripts/strongswan-health-check.sh "$aggregator_ip" "$branch_ip" ~/.ssh/${KEY_NAME}.pem; then
        print_status "Health check completed successfully!"
    else
        print_warning "Health check detected some issues. Please review the output above."
    fi
}

# Function to display deployment summary
display_summary() {
    local aggregator_ip=$1
    local branch_ip=$2
    
    echo ""
    echo -e "${GREEN}🎉 SD-WAN Deployment Complete!${NC}"
    echo "==============================="
    echo ""
    echo "📊 Deployment Summary:"
    echo "  Environment: $ENVIRONMENT"
    echo "  AWS Region: $REGION"
    echo "  Aggregator IP: $aggregator_ip"
    echo "  Branch IP: $branch_ip"
    echo ""
    echo "🔐 SSH Access:"
    echo "  Aggregator: ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@$aggregator_ip"
    echo "  Branch:     ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@$branch_ip"
    echo ""
    echo "🛠️  Management Commands:"
    echo "  Health Check: ./scripts/strongswan-health-check.sh $aggregator_ip $branch_ip"
    echo "  IPsec Status: ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@$aggregator_ip 'sudo strongswan status'"
    echo ""
    echo "💰 Cost Information:"
    echo "  Instance Type: t3.micro (Free Tier eligible)"
    echo "  Estimated Cost: \$0/month (within Free Tier limits)"
    echo ""
    echo "📚 Documentation:"
    echo "  Setup Guide: docs/SETUP_GUIDE.md"
    echo "  IaC Guide: docs/IAC_AWS_DEPLOYMENT.md"
    echo "  Cost Optimization: docs/COST_OPTIMIZATION.md"
    echo ""
    echo "🚀 Next Steps:"
    echo "  1. Test IPsec connectivity between sites"
    echo "  2. Configure BGP routing for dynamic paths"
    echo "  3. Implement QoS and traffic shaping"
    echo "  4. Set up monitoring and alerting"
    echo ""
}

# Function to cleanup on failure
cleanup_on_failure() {
    print_error "Deployment failed. Cleaning up..."
    
    # Cleanup branch
    if [ -d "terraform/branch/" ]; then
        cd terraform/branch/
        if [ -f "terraform.tfstate" ]; then
            terraform destroy -auto-approve || true
        fi
        cd ../..
    fi
    
    # Cleanup aggregator
    if [ -d "terraform/" ]; then
        cd terraform/
        if [ -f "terraform.tfstate" ]; then
            terraform destroy -auto-approve || true
        fi
        cd ..
    fi
    
    # Remove temporary files
    rm -f aggregator_ip.txt branch_ip.txt
}

# Function to handle script interruption
handle_interrupt() {
    print_warning "Deployment interrupted by user"
    cleanup_on_failure
    exit 1
}

# Set trap for cleanup
trap handle_interrupt SIGINT SIGTERM

# Main execution flow
main() {
    print_info "Starting automated SD-WAN deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy aggregator first
    deploy_aggregator
    local aggregator_ip=$(cat aggregator_ip.txt)
    
    # Deploy branch with aggregator IP
    deploy_branch "$aggregator_ip"
    local branch_ip=$(cat branch_ip.txt)
    
    # Wait for both instances to be ready
    wait_for_instances "$aggregator_ip" "$branch_ip"
    
    # Give services time to start
    print_info "Waiting for services to initialize..."
    sleep 30
    
    # Run health check
    run_health_check "$aggregator_ip" "$branch_ip"
    
    # Display summary
    display_summary "$aggregator_ip" "$branch_ip"
    
    # Clean up temporary files
    rm -f aggregator_ip.txt branch_ip.txt
    
    print_status "Deployment completed successfully!"
}

# Show usage if help requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Automated SD-WAN deployment script for AWS"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --cleanup      Clean up existing deployment"
    echo ""
    echo "Environment variables:"
    echo "  ENVIRONMENT    Deployment environment (default: test)"
    echo "  KEY_NAME       SSH key name (default: vyos-demo-key)"
    echo "  REGION         AWS region (default: ap-southeast-1)"
    echo ""
    echo "Prerequisites:"
    echo "  - Terraform >= 1.0"
    echo "  - AWS CLI configured with credentials"
    echo "  - Sufficient AWS permissions for EC2, VPC, and Security Groups"
    echo ""
    exit 0
fi

# Cleanup option
if [ "$1" = "--cleanup" ]; then
    print_info "Cleaning up existing deployment..."
    cleanup_on_failure
    print_status "Cleanup completed!"
    exit 0
fi

# Override environment variables if set
ENVIRONMENT=${ENVIRONMENT:-"test"}
KEY_NAME=${KEY_NAME:-"vyos-demo-key"}
REGION=${REGION:-"ap-southeast-1"}

# Run main function
main