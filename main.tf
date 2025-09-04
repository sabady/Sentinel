terraform {
  required_version = ">= 1.0"

  # S3 Backend Configuration for Remote State Storage
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

# GitHub OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "github-oidc-provider"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
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

# Route 53 Private Hosted Zone for Sentinel
resource "aws_route53_zone" "sentinel_private" {
  name = "sentinel.local"

  vpc {
    vpc_id = module.vpc["vpc_gateway"].vpc_id
  }

  vpc {
    vpc_id = module.vpc["vpc_backend"].vpc_id
  }

  tags = {
    Name        = "sentinel-private-zone"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
}

# DNS Records for Services
resource "aws_route53_record" "gateway_proxy" {
  zone_id = aws_route53_zone.sentinel_private.zone_id
  name    = "gateway.sentinel.local"
  type    = "A"
  ttl     = 300

  records = [
    # This will be updated by External DNS or manually with LoadBalancer IP
    "10.0.1.10"  # Placeholder - will be replaced with actual LoadBalancer IP
  ]
}

resource "aws_route53_record" "backend_service" {
  zone_id = aws_route53_zone.sentinel_private.zone_id
  name    = "backend.sentinel.local"
  type    = "A"
  ttl     = 300

  records = [
    # This will be updated by External DNS or manually with service IP
    "10.1.1.10"  # Placeholder - will be replaced with actual service IP
  ]
}

# CNAME for easy access
resource "aws_route53_record" "sentinel_app" {
  zone_id = aws_route53_zone.sentinel_private.zone_id
  name    = "app.sentinel.local"
  type    = "CNAME"
  ttl     = 300

  records = ["gateway.sentinel.local"]
}

# IAM Role for GitHub Actions - Terraform Operations
resource "aws_iam_role" "github_actions_terraform" {
  name = "github-actions-terraform-sentinel"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "github-actions-terraform-role"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
}

# IAM Role for GitHub Actions - EKS Operations
resource "aws_iam_role" "github_actions_eks" {
  name = "github-actions-eks-sentinel"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "github-actions-eks-role"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
}

# IAM Policy for Terraform Operations
resource "aws_iam_policy" "github_actions_terraform" {
  name        = "github-actions-terraform-sentinel"
  description = "Policy for GitHub Actions to perform Terraform operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::sentinel-terraform-state-721500739616",
          "arn:aws:s3:::sentinel-terraform-state-721500739616/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "eks:*",
          "iam:*",
          "route53:*",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "github-actions-terraform-policy"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
}

# IAM Policy for EKS Operations
resource "aws_iam_policy" "github_actions_eks" {
  name        = "github-actions-eks-sentinel"
  description = "Policy for GitHub Actions to perform EKS operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-*"
        ]
      }
    ]
  })

  tags = {
    Name        = "github-actions-eks-policy"
    Environment = "production"
    Project     = "sentinel"
    Terraform   = "true"
  }
}

# Attach policies to roles
resource "aws_iam_role_policy_attachment" "github_actions_terraform" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.github_actions_terraform.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_eks" {
  role       = aws_iam_role.github_actions_eks.name
  policy_arn = aws_iam_policy.github_actions_eks.arn
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

  # Ensure proper cleanup order
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

  # Ensure proper cleanup order
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

  # Ensure proper cleanup order
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

  # Ensure proper cleanup order
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

# EKS Clusters
module "eks" {
  for_each = local.vpcs
  source   = "terraform-aws-modules/eks/aws"
  version  = "~> 20.0"

  cluster_name    = "eks-${each.value.name}"
  cluster_version = "1.31"

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

      # Let EKS manage node group security groups automatically
      # This prevents cross-reference issues and ensures proper cleanup
      # vpc_security_group_ids = [
      #   each.key == "vpc_gateway" ? aws_security_group.gateway_worker_nodes.id : aws_security_group.backend_worker_nodes.id
      # ]

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

  # Let EKS manage security groups automatically to avoid cross-reference issues
  # This prevents the cross-reference problems we encountered during cleanup
  # cluster_security_group_id = each.key == "vpc_gateway" ? aws_security_group.gateway_eks_cluster.id : aws_security_group.backend_eks_cluster.id

  # EKS will create and manage its own security groups
  # This ensures proper cleanup and avoids cross-reference issues
  create_cluster_security_group = true
  create_node_security_group    = true

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

# Additional Security Group Rules for EKS-Managed Security Groups
# These rules will be applied to the EKS-managed security groups to ensure proper communication

# Gateway EKS Node Group - Allow HTTP from internet
resource "aws_security_group_rule" "gateway_eks_nodes_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP from internet to gateway EKS nodes"
  security_group_id = module.eks["vpc_gateway"].node_security_group_id
}

# Backend EKS Node Group - Allow HTTP from Gateway VPC only
resource "aws_security_group_rule" "backend_eks_nodes_http_from_gateway" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = module.eks["vpc_gateway"].node_security_group_id
  description              = "Allow HTTP from gateway EKS nodes to backend EKS nodes"
  security_group_id        = module.eks["vpc_backend"].node_security_group_id
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

# DNS Outputs
output "route53_zone_id" {
  description = "Route 53 Private Hosted Zone ID for Sentinel"
  value       = aws_route53_zone.sentinel_private.zone_id
}

output "route53_zone_name_servers" {
  description = "Route 53 Private Hosted Zone Name Servers"
  value       = aws_route53_zone.sentinel_private.name_servers
}

output "dns_gateway_url" {
  description = "DNS URL for Gateway Service"
  value       = "http://gateway.sentinel.local"
}

output "dns_backend_url" {
  description = "DNS URL for Backend Service"
  value       = "http://backend.sentinel.local"
}

output "dns_app_url" {
  description = "DNS URL for Main Application"
  value       = "http://app.sentinel.local"
}

# OIDC and IAM Outputs
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC Identity Provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_terraform_role_arn" {
  description = "ARN of the GitHub Actions Terraform IAM Role"
  value       = aws_iam_role.github_actions_terraform.arn
}

output "github_actions_eks_role_arn" {
  description = "ARN of the GitHub Actions EKS IAM Role"
  value       = aws_iam_role.github_actions_eks.arn
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}


