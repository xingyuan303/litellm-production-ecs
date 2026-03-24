# ============================================
# VPC and Network Configuration
# ============================================

# Use default VPC (for simplicity)
# For production, consider creating a dedicated VPC
resource "aws_default_vpc" "default_vpc" {
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Default subnets in different availability zones
resource "aws_default_subnet" "ecs_az1" {
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-subnet-az1"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_default_subnet" "ecs_az2" {
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.project_name}-subnet-az2"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_default_subnet" "ecs_az3" {
  availability_zone = "${var.aws_region}c"

  tags = {
    Name        = "${var.project_name}-subnet-az3"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Note: For production, consider creating a custom VPC with:
# - Public and private subnets
# - NAT Gateways
# - VPC Endpoints for AWS services
# - Network ACLs
#
# Example structure:
# resource "aws_vpc" "main" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_hostnames = true
#   enable_dns_support   = true
# }
#
# resource "aws_subnet" "public" {
#   count             = 3
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = "10.0.${count.index}.0/24"
#   availability_zone = data.aws_availability_zones.available.names[count.index]
# }
#
# resource "aws_subnet" "private" {
#   count             = 3
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = "10.0.${count.index + 10}.0/24"
#   availability_zone = data.aws_availability_zones.available.names[count.index]
# }
