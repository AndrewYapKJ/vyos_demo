# Branch Office Terraform Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type for VyOS Branch"
  type        = string
  default     = "t3.micro"  # Free tier eligible
}

variable "key_name" {
  description = "AWS key pair name for SSH access"
  type        = string
  default     = "vyos-demo-key"
}

variable "aggregator_public_ip" {
  description = "Public IP address of the aggregator"
  type        = string
  default     = "18.141.25.25"  # Your aggregator IP
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "test"
}

# Data sources
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ami" "branch" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
  
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Security Group for Branch
resource "aws_security_group" "branch_sg" {
  name        = "vyos-branch-sg-${var.environment}"
  description = "Security group for VyOS Branch Office"
  vpc_id      = data.aws_vpc.default.id

  # IPsec ESP
  ingress {
    description = "IPsec ESP"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IPsec NAT-T
  ingress {
    description = "IPsec NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IKE
  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP for status page
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP for health checks
  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "vyos-branch-sg-${var.environment}"
    Environment = var.environment
    Project     = "vyos-sdwan"
  }
}

# User data for branch configuration
locals {
  user_data = templatefile("${path.module}/user-data.sh", {
    aggregator_public_ip = var.aggregator_public_ip
  })
}

# EC2 Instance for VyOS Branch
resource "aws_instance" "vyos_branch" {
  ami                         = data.aws_ami.branch.id
  instance_type              = var.instance_type
  key_name                   = var.key_name
  subnet_id                  = data.aws_subnets.default.ids[0]
  vpc_security_group_ids     = [aws_security_group.branch_sg.id]
  associate_public_ip_address = true
  
  user_data = local.user_data

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name        = "vyos-branch-${var.environment}"
    Environment = var.environment
    Project     = "vyos-sdwan"
    Role        = "branch"
  }
}

# Outputs
output "branch_public_ip" {
  description = "Public IP address of VyOS branch"
  value       = aws_instance.vyos_branch.public_ip
}

output "branch_private_ip" {
  description = "Private IP address of VyOS branch"
  value       = aws_instance.vyos_branch.private_ip
}

output "branch_instance_id" {
  description = "Instance ID of VyOS branch"
  value       = aws_instance.vyos_branch.id
}

output "ssh_command" {
  description = "SSH command to connect to branch"
  value       = "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.vyos_branch.public_ip}"
}

output "web_status_url" {
  description = "Web status URL for branch"
  value       = "http://${aws_instance.vyos_branch.public_ip}"
}

output "tunnel_status" {
  description = "Commands to check tunnel"
  value       = "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.vyos_branch.public_ip} 'sudo strongswan status'"
}

output "test_connectivity" {
  description = "Test connectivity between sites"
  value       = "./validation/test-connectivity.sh ${var.aggregator_public_ip} ${aws_instance.vyos_branch.public_ip} ${var.key_name}.pem"
}