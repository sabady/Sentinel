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
  region = "us-west-2" # Change this to your preferred region
}

locals {
  vpcs = {
    vpc_gateway = {
      name            = "vpc-gateway"
      cidr            = "10.0.0.0/16"
      private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
      public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
    }
    vpc_backend = {
      name            = "vpc-backend"
      cidr            = "10.1.0.0/16"
      private_subnets = ["10.1.1.0/24", "10.1.2.0/24"]
      public_subnets  = ["10.1.101.0/24", "10.1.102.0/24"]
    }
  }
}

module "vpc" {
  for_each = local.vpcs
  source   = "terraform-aws-modules/vpc/aws"
  version  = "~> 5.0"

  name = each.value.name
  cidr = each.value.cidr

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = each.value.private_subnets
  public_subnets  = each.value.public_subnets

  # NAT Gateway Configuration: Single NAT Gateway per VPC for cost optimization
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_vpn_gateway = false

  tags = {
    Environment = "production"
    Project     = "sentinel"
    VPC         = each.value.name
    Terraform   = "true"
  }

  private_subnet_tags = {
    Type = "private"
    VPC  = each.value.name
  }

  public_subnet_tags = {
    Type = "public"
    VPC  = each.value.name
  }
}

# VPC Peering
resource "aws_vpc_peering_connection" "gateway_to_backend" {
  vpc_id      = module.vpc["vpc_gateway"].vpc_id
  peer_vpc_id = module.vpc["vpc_backend"].vpc_id
  auto_accept = true

  tags = {
    Name        = "gateway-to-backend-peering"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
}

# Route table updates for VPC Gateway to reach VPC Backend
resource "aws_route" "gateway_private_to_backend" {
  count = length(module.vpc["vpc_gateway"].private_route_table_ids)

  route_table_id            = module.vpc["vpc_gateway"].private_route_table_ids[count.index]
  destination_cidr_block    = module.vpc["vpc_backend"].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.gateway_to_backend.id
}

# Route table updates for VPC Backend to reach VPC Gateway
resource "aws_route" "backend_private_to_gateway" {
  count = length(module.vpc["vpc_backend"].private_route_table_ids)

  route_table_id            = module.vpc["vpc_backend"].private_route_table_ids[count.index]
  destination_cidr_block    = module.vpc["vpc_gateway"].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.gateway_to_backend.id
}

# Security Groups for EKS Clusters
# Gateway VPC Security Groups
resource "aws_security_group" "gateway_eks_cluster" {
  name_prefix = "gateway-eks-cluster-"
  vpc_id      = module.vpc["vpc_gateway"].vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "gateway-eks-cluster-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_gateway"
  }
}

resource "aws_security_group" "gateway_worker_nodes" {
  name_prefix = "gateway-worker-nodes-"
  vpc_id      = module.vpc["vpc_gateway"].vpc_id

  # Allow internet access on port 80
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access from internet"
  }

  # Allow Kubernetes internal communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [module.vpc["vpc_gateway"].vpc_cidr_block]
    description = "Allow all TCP ports from VPC CIDR for internal communication"
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "gateway-worker-nodes-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_gateway"
  }
}

# Backend VPC Security Groups
resource "aws_security_group" "backend_eks_cluster" {
  name_prefix = "backend-eks-cluster-"
  vpc_id      = module.vpc["vpc_backend"].vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "backend-eks-cluster-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_backend"
  }
}

resource "aws_security_group" "backend_worker_nodes" {
  name_prefix = "backend-worker-nodes-"
  vpc_id      = module.vpc["vpc_backend"].vpc_id

  # Allow port 80 from gateway worker nodes only
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway_worker_nodes.id]
    description     = "Allow port 80 from gateway worker nodes"
  }

  # Allow Kubernetes internal communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [module.vpc["vpc_backend"].vpc_cidr_block]
    description = "Allow all TCP ports from VPC CIDR for internal communication"
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "backend-worker-nodes-sg"
    Environment = "production"
    Project     = "sentinel"
    VPC         = "vpc_backend"
  }
}

# EKS Clusters
module "eks" {
  for_each = local.vpcs
  source   = "terraform-aws-modules/eks/aws"
  version  = "~> 20.0"

  cluster_name    = "eks-${each.value.name}"
  cluster_version = "1.28"

  vpc_id     = module.vpc[each.key].vpc_id
  subnet_ids = module.vpc[each.key].private_subnets

  # EKS Control Plane Security Group
  cluster_security_group_additional_rules = {
    ingress_nodes_443 = {
      description                = "Node groups to cluster API"
      protocol                   = "tcp"
      from_port                  = 443
      to_port                    = 443
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Node Groups
  eks_managed_node_groups = {
    general = {
      desired_size = 2
      min_size     = 1
      max_size     = 3

      instance_types = ["t4g.medium"]
      capacity_type  = "SPOT"

      # Node Group Security Group
      vpc_security_group_ids = [
        each.key == "vpc_gateway" ? aws_security_group.gateway_worker_nodes.id : aws_security_group.backend_worker_nodes.id
      ]

      labels = {
        Environment  = "production"
        Project      = "sentinel"
        VPC          = each.value.name
        InstanceType = "t4g.medium"
        CapacityType = "SPOT"
      }

      tags = {
        ExtraTag     = "eks-node-group"
        InstanceType = "t4g.medium"
        CapacityType = "SPOT"
      }
    }
  }

  # Cluster Security Group
  cluster_security_group_id = each.key == "vpc_gateway" ? aws_security_group.gateway_eks_cluster.id : aws_security_group.backend_eks_cluster.id

  # Tags
  cluster_tags = {
    Environment = "production"
    Project     = "sentinel"
    VPC         = each.value.name
  }

  tags = {
    Environment = "production"
    Project     = "sentinel"
    VPC         = each.value.name
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
  description = "List of IDs of private subnets in VPC Gateway"
  value       = module.vpc["vpc_gateway"].private_subnets
}

output "vpc_backend_private_subnets" {
  description = "List of IDs of private subnets in VPC Backend"
  value       = module.vpc["vpc_backend"].private_subnets
}

output "vpc_gateway_public_subnets" {
  description = "List of IDs of public subnets in VPC Gateway"
  value       = module.vpc["vpc_gateway"].public_subnets
}

output "vpc_backend_public_subnets" {
  description = "List of IDs of public subnets in VPC Backend"
  value       = module.vpc["vpc_backend"].public_subnets
}

# Note: NAT Gateway outputs are not available from the VPC module
# Use AWS CLI or console to view NAT Gateway information if needed
# 
# To get NAT Gateway information after deployment:
# aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${{ module.vpc["vpc_gateway"].vpc_id }}"
# aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${{ module.vpc["vpc_backend"].vpc_id }}"



output "vpc_gateway_route_table_ids" {
  description = "Route Table IDs in VPC Gateway"
  value       = module.vpc["vpc_gateway"].private_route_table_ids
}

output "vpc_backend_route_table_ids" {
  description = "Route Table IDs in VPC Backend"
  value       = module.vpc["vpc_backend"].private_route_table_ids
}

output "vpc_gateway_cidr_block" {
  description = "The CIDR block of VPC Gateway"
  value       = module.vpc["vpc_gateway"].vpc_cidr_block
}

output "vpc_backend_cidr_block" {
  description = "The CIDR block of VPC Backend"
  value       = module.vpc["vpc_backend"].vpc_cidr_block
}

output "vpc_peering_connection_id" {
  description = "The ID of the VPC peering connection between gateway and backend VPCs"
  value       = aws_vpc_peering_connection.gateway_to_backend.id
}

# Security Group Outputs
output "gateway_eks_cluster_sg_id" {
  description = "Security Group ID for Gateway EKS Cluster"
  value       = aws_security_group.gateway_eks_cluster.id
}

output "gateway_worker_nodes_sg_id" {
  description = "Security Group ID for Gateway Worker Nodes"
  value       = aws_security_group.gateway_worker_nodes.id
}

output "backend_eks_cluster_sg_id" {
  description = "Security Group ID for Backend EKS Cluster"
  value       = aws_security_group.backend_eks_cluster.id
}

output "backend_worker_nodes_sg_id" {
  description = "Security Group ID for Backend Worker Nodes"
  value       = aws_security_group.backend_worker_nodes.id
}
