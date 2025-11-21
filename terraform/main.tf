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
  description = "EC2 instance type for VyOS"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "AWS key pair name for SSH access"
  type        = string
  default     = "vyos-key"
}

variable "branch_public_ip" {
  description = "Public IP address of the branch office"
  type        = string
  default     = "203.0.113.50"
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

data "aws_ami" "vyos" {
  most_recent = true
  owners      = ["679593333241"] # VyOS AMI owner
  
  filter {
    name   = "name"
    values = ["vyos-1.5-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for VyOS
resource "aws_security_group" "vyos_sg" {
  name        = "vyos-aggregator-sg-${var.environment}"
  description = "Security group for VyOS Aggregator"
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

  # HTTPS Web GUI
  ingress {
    description = "HTTPS Web GUI"
    from_port   = 443
    to_port     = 443
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
    Name        = "vyos-aggregator-sg-${var.environment}"
    Environment = var.environment
    Project     = "vyos-sdwan"
  }
}

# Generate user data script with VyOS configuration
data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")
  vars = {
    branch_public_ip = var.branch_public_ip
  }
}

# EC2 Instance for VyOS Aggregator
resource "aws_instance" "vyos_aggregator" {
  ami                         = data.aws_ami.vyos.id
  instance_type              = var.instance_type
  key_name                   = var.key_name
  subnet_id                  = data.aws_subnets.default.ids[0]
  vpc_security_group_ids     = [aws_security_group.vyos_sg.id]
  associate_public_ip_address = true
  
  user_data = data.template_file.user_data.rendered

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 10
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "vyos-aggregator-${var.environment}"
    Environment = var.environment
    Project     = "vyos-sdwan"
    Role        = "aggregator"
  }
}

# Elastic IP for consistent addressing
resource "aws_eip" "vyos_eip" {
  domain = "vpc"
  
  tags = {
    Name        = "vyos-aggregator-eip-${var.environment}"
    Environment = var.environment
    Project     = "vyos-sdwan"
  }
}

# Associate Elastic IP with instance
resource "aws_eip_association" "vyos_eip_assoc" {
  instance_id   = aws_instance.vyos_aggregator.id
  allocation_id = aws_eip.vyos_eip.id
}

# Outputs
output "vyos_public_ip" {
  description = "Public IP address of VyOS aggregator"
  value       = aws_eip.vyos_eip.public_ip
}

output "vyos_private_ip" {
  description = "Private IP address of VyOS aggregator"
  value       = aws_instance.vyos_aggregator.private_ip
}

output "vyos_instance_id" {
  description = "Instance ID of VyOS aggregator"
  value       = aws_instance.vyos_aggregator.id
}

output "ssh_command" {
  description = "SSH command to connect to VyOS"
  value       = "ssh -i ${var.key_name}.pem vyos@${aws_eip.vyos_eip.public_ip}"
}

output "web_gui_url" {
  description = "Web GUI URL for VyOS management"
  value       = "https://${aws_eip.vyos_eip.public_ip}"
}

output "security_group_id" {
  description = "Security group ID for VyOS"
  value       = aws_security_group.vyos_sg.id
}