terraform {
  required_version = ">= 1.0"

  # S3 Backend Configuration for Remote State Storage
  backend "s3" {
    bucket       = "sentinel-terraform-state-721500739616"
    key          = "infrastructure/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true

    # Enable state locking using lockfile instead of DynamoDB
    # This provides local file-based locking for state consistency
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2" # Change this to your preferred region
}

# Get current AWS account ID for unique bucket naming
data "aws_caller_identity" "current" {}

locals {
  vpcs = {
    vpc_gateway = {
      name               = "gateway"
      cidr               = "10.0.0.0/16"
      availability_zones = ["us-west-2a", "us-west-2b"]
      private_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
      public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]
    }
    vpc_backend = {
      name               = "backend"
      cidr               = "10.1.0.0/16"
      availability_zones = ["us-west-2a", "us-west-2b"]
      private_subnets    = ["10.1.1.0/24", "10.1.2.0/24"]
      public_subnets     = ["10.1.101.0/24", "10.1.102.0/24"]
    }
  }
}

# S3 Backend resources are defined in backend.tf

# VPCs
module "vpc" {
  for_each = local.vpcs
  source   = "terraform-aws-modules/vpc/aws"
  version  = "~> 5.0"

  name = "vpc-${each.value.name}"
  cidr = each.value.cidr

  azs             = each.value.availability_zones
  private_subnets = each.value.private_subnets
  public_subnets  = each.value.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  enable_vpn_gateway     = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "production"
    Project     = "sentinel"
    VPC         = each.value.name
  }
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "gateway_to_backend" {
  vpc_id      = module.vpc["vpc_gateway"].vpc_id
  peer_vpc_id = module.vpc["vpc_backend"].vpc_id
  auto_accept = true

  tags = {
    Name        = "gateway-to-backend-peering"
    Environment = "production"
    Project     = "sentinel"
  }
}

# Route for Gateway VPC to reach Backend VPC
resource "aws_route" "gateway_to_backend" {
  route_table_id            = module.vpc["vpc_gateway"].private_route_table_ids[0]
  destination_cidr_block    = module.vpc["vpc_backend"].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.gateway_to_backend.id
}

# Route for Backend VPC to reach Gateway VPC
resource "aws_route" "backend_to_gateway" {
  route_table_id            = module.vpc["vpc_backend"].private_route_table_ids[0]
  destination_cidr_block    = module.vpc["vpc_gateway"].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.gateway_to_backend.id
}

# Security Groups
resource "aws_security_group" "gateway_eks_cluster" {
  name_prefix = "gateway-eks-cluster-"
  vpc_id      = module.vpc["vpc_gateway"].vpc_id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "gateway-eks-cluster-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_gateway"
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "gateway_worker_nodes" {
  name_prefix = "gateway-worker-nodes-"
  vpc_id      = module.vpc["vpc_gateway"].vpc_id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "gateway-worker-nodes-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_gateway"
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "backend_eks_cluster" {
  name_prefix = "backend-eks-cluster-"
  vpc_id      = module.vpc["vpc_backend"].vpc_id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "backend-eks-cluster-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_backend"
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "backend_worker_nodes" {
  name_prefix = "backend-worker-nodes-"
  vpc_id      = module.vpc["vpc_backend"].vpc_id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway_worker_nodes.id]
    description     = "Allow HTTP from gateway worker nodes only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "backend-worker-nodes-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_backend"
    ManagedBy   = "terraform"
  }
}

# Outputs
output "vpc_gateway_id" {
  description = "The ID of VPC Gateway"
  value       = module.vpc["vpc_gateway"].vpc_id
}

output "vpc_backend_id" {
  description = "The ID of VPC Backend"
  value       = module.vpc["vpc_backend"].vpc_id
}

output "vpc_gateway_private_subnets" {
  description = "Private subnet IDs for VPC Gateway"
  value       = module.vpc["vpc_gateway"].private_subnets
}

output "vpc_backend_private_subnets" {
  description = "Private subnet IDs for VPC Backend"
  value       = module.vpc["vpc_backend"].private_subnets
}

output "vpc_gateway_public_subnets" {
  description = "Public subnet IDs for VPC Gateway"
  value       = module.vpc["vpc_gateway"].public_subnets
}

output "vpc_backend_public_subnets" {
  description = "Public subnet IDs for VPC Backend"
  value       = module.vpc["vpc_backend"].public_subnets
}

output "vpc_peering_connection_id" {
  description = "The ID of the VPC peering connection"
  value       = aws_vpc_peering_connection.gateway_to_backend.id
}

# S3 backend outputs are defined in backend.tf

output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "The AWS region"
  value       = "us-west-2"
}
