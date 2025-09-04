# Disabled Resources - Requires additional IAM permissions
# These resources are commented out due to permission restrictions
# Uncomment and configure when you have the necessary IAM permissions

# =============================================================================
# GITHUB OIDC FEDERATION RESOURCES
# =============================================================================

# GitHub OIDC Provider for secure deployments without long-lived credentials
# resource "aws_iam_openid_connect_provider" "github" {
#   url = "https://token.actions.githubusercontent.com"
# 
#   client_id_list = [
#     "sts.amazonaws.com",
#   ]
# 
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1",
#     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
#   ]
# 
#   tags = {
#     Name        = "github-oidc-provider"
#     Environment = "production"
#     Project     = "sentinel"
#   }
# }

# IAM Role for GitHub Actions Terraform operations
# resource "aws_iam_role" "github_actions_terraform" {
#   name = "github-actions-terraform-role"
# 
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = aws_iam_openid_connect_provider.github.arn
#         }
#         Condition = {
#           StringEquals = {
#             "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#           }
#           StringLike = {
#             "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
#           }
#         }
#       }
#     ]
#   })
# 
#   tags = {
#     Name        = "github-actions-terraform-role"
#     Environment = "production"
#     Project     = "sentinel"
#   }
# }

# IAM Role for GitHub Actions EKS operations
# resource "aws_iam_role" "github_actions_eks" {
#   name = "github-actions-eks-role"
# 
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = aws_iam_openid_connect_provider.github.arn
#         }
#         Condition = {
#           StringEquals = {
#             "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#           }
#           StringLike = {
#             "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
#           }
#         }
#       }
#     ]
#   })
# 
#   tags = {
#     Name        = "github-actions-eks-role"
#     Environment = "production"
#     Project     = "sentinel"
#   }
# }

# IAM Policy for GitHub Actions Terraform operations
# resource "aws_iam_policy" "github_actions_terraform" {
#   name        = "github-actions-terraform-policy"
#   description = "Policy for GitHub Actions to perform Terraform operations"
# 
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:PutObject",
#           "s3:DeleteObject",
#           "s3:ListBucket"
#         ]
#         Resource = [
#           aws_s3_bucket.terraform_state.arn,
#           "${aws_s3_bucket.terraform_state.arn}/*"
#         ]
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "dynamodb:GetItem",
#           "dynamodb:PutItem",
#           "dynamodb:DeleteItem"
#         ]
#         Resource = aws_dynamodb_table.terraform_state_lock.arn
#       }
#     ]
#   })
# 
#   tags = {
#     Name        = "github-actions-terraform-policy"
#     Environment = "production"
#     Project     = "sentinel"
#   }
# }

# IAM Policy for GitHub Actions EKS operations
# resource "aws_iam_policy" "github_actions_eks" {
#   name        = "github-actions-eks-policy"
#   description = "Policy for GitHub Actions to perform EKS operations"
# 
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "eks:DescribeCluster",
#           "eks:ListClusters",
#           "eks:UpdateClusterConfig",
#           "eks:UpdateClusterVersion",
#           "eks:CreateNodegroup",
#           "eks:DeleteNodegroup",
#           "eks:DescribeNodegroup",
#           "eks:ListNodegroups",
#           "eks:UpdateNodegroupConfig",
#           "eks:UpdateNodegroupVersion"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
# 
#   tags = {
#     Name        = "github-actions-eks-policy"
#     Environment = "production"
#     Project     = "sentinel"
#   }
# }

# Attach Terraform policy to GitHub Actions Terraform role
# resource "aws_iam_role_policy_attachment" "github_actions_terraform" {
#   role       = aws_iam_role.github_actions_terraform.name
#   policy_arn = aws_iam_policy.github_actions_terraform.arn
# }

# Attach EKS policy to GitHub Actions EKS role
# resource "aws_iam_role_policy_attachment" "github_actions_eks" {
#   role       = aws_iam_role.github_actions_eks.name
#   policy_arn = aws_iam_policy.github_actions_eks.arn
# }

# =============================================================================
# ROUTE 53 DNS RESOURCES
# =============================================================================

# Private Hosted Zone for internal DNS resolution
# resource "aws_route53_zone" "sentinel_private" {
#   name = "sentinel.local"
# 
#   vpc {
#     vpc_id = module.vpc["vpc_gateway"].vpc_id
#   }
# 
#   vpc {
#     vpc_id = module.vpc["vpc_backend"].vpc_id
#   }
# 
#   tags = {
#     Name        = "sentinel-private-zone"
#     Environment = "production"
#     Project     = "sentinel"
#   }
# }

# DNS record for gateway proxy
# resource "aws_route53_record" "gateway_proxy" {
#   zone_id = aws_route53_zone.sentinel_private.zone_id
#   name    = "gateway.sentinel.local"
#   type    = "A"
#   ttl     = 300
# 
#   records = [module.vpc["vpc_gateway"].vpc_cidr_block]
# }

# DNS record for backend service
# resource "aws_route53_record" "backend_service" {
#   zone_id = aws_route53_zone.sentinel_private.zone_id
#   name    = "backend.sentinel.local"
#   type    = "A"
#   ttl     = 300
# 
#   records = [module.vpc["vpc_backend"].vpc_cidr_block]
# }

# DNS record for the main application
# resource "aws_route53_record" "sentinel_app" {
#   zone_id = aws_route53_zone.sentinel_private.zone_id
#   name    = "app.sentinel.local"
#   type    = "CNAME"
#   ttl     = 300
# 
#   records = ["gateway.sentinel.local"]
# }

# =============================================================================
# EKS CLUSTER RESOURCES
# =============================================================================

# EKS Clusters
# module "eks" {
#   for_each = local.vpcs
#   source   = "terraform-aws-modules/eks/aws"
#   version  = "~> 20.0"
#
#   cluster_name    = "eks-${each.value.name}"
#   cluster_version = "1.31"
#
#   vpc_id     = module.vpc[each.key].vpc_id
#   subnet_ids = module.vpc[each.key].private_subnets
#
#   # EKS Control Plane Security Group
#   cluster_security_group_additional_rules = {
#     ingress_nodes_443 = {
#       description                = "Node groups to cluster API"
#       protocol                   = "tcp"
#       from_port                  = 443
#       to_port                    = 443
#       type                       = "ingress"
#       source_node_security_group = true
#     }
#   }
#
#   # Node Groups
#   eks_managed_node_groups = {
#     general = {
#       desired_size = 2
#       min_size     = 1
#       max_size     = 3
#
#       instance_types = ["t4g.medium"]
#       capacity_type  = "SPOT"
#
#       # Let EKS manage node group security groups automatically
#       # This prevents cross-reference issues and ensures proper cleanup
#       # vpc_security_group_ids = [
#       #   each.key == "vpc_gateway" ? aws_security_group.gateway_worker_nodes.id : aws_security_group.backend_worker_nodes.id
#       # ]
#
#       labels = {
#         Environment  = "production"
#         Project      = "sentinel"
#         VPC          = each.value.name
#         InstanceType = "t4g.medium"
#         CapacityType = "SPOT"
#       }
#
#       tags = {
#         ExtraTag     = "eks-node-group"
#         InstanceType = "t4g.medium"
#         CapacityType = "SPOT"
#       }
#     }
#   }
#
#   # Let EKS manage security groups automatically to avoid cross-reference issues
#   # This prevents the cross-reference problems we encountered during cleanup
#   # cluster_security_group_id = each.key == "vpc_gateway" ? aws_security_group.gateway_eks_cluster.id : aws_security_group.backend_eks_cluster.id
#
#   # EKS will create and manage its own security groups
#   # This ensures proper cleanup and avoids cross-reference issues
#   create_cluster_security_group = true
#   create_node_security_group    = true
#
#   # Tags
#   cluster_tags = {
#     Environment = "production"
#     Project     = "sentinel"
#     VPC         = each.value.name
#   }
#
#   tags = {
#     Environment = "production"
#     Project     = "sentinel"
#     VPC         = each.value.name
#   }
# }

# =============================================================================
# EKS SECURITY GROUP RULES
# =============================================================================

# Additional Security Group Rules for EKS-Managed Security Groups
# These rules will be applied to the EKS-managed security groups to ensure proper communication
#
# # Gateway EKS Node Group - Allow HTTP from internet
# resource "aws_security_group_rule" "gateway_eks_nodes_http" {
#   type              = "ingress"
#   from_port         = 80
#   to_port           = 80
#   protocol          = "tcp"
#   cidr_blocks       = ["0.0.0.0/0"]
#   description       = "Allow HTTP from internet to gateway EKS nodes"
#   security_group_id = module.eks["vpc_gateway"].node_security_group_id
# }
#
# # Backend EKS Node Group - Allow HTTP from Gateway VPC only
# resource "aws_security_group_rule" "backend_eks_nodes_http_from_gateway" {
#   type                     = "ingress"
#   from_port                = 80
#   to_port                  = 80
#   protocol                 = "tcp"
#   source_security_group_id = module.eks["vpc_gateway"].node_security_group_id
#   description              = "Allow HTTP from gateway EKS nodes to backend EKS nodes"
#   security_group_id        = module.eks["vpc_backend"].node_security_group_id
# }

# =============================================================================
# DISABLED OUTPUTS
# =============================================================================

# OIDC Provider ARN
# output "github_oidc_provider_arn" {
#   description = "The ARN of the GitHub OIDC Provider"
#   value       = aws_iam_openid_connect_provider.github.arn
# }

# GitHub Actions Terraform Role ARN
# output "github_actions_terraform_role_arn" {
#   description = "The ARN of the GitHub Actions Terraform role"
#   value       = aws_iam_role.github_actions_terraform.arn
# }

# GitHub Actions EKS Role ARN
# output "github_actions_eks_role_arn" {
#   description = "The ARN of the GitHub Actions EKS role"
#   value       = aws_iam_role.github_actions_eks.arn
# }

# Route 53 Zone ID
# output "route53_zone_id" {
#   description = "The ID of the Route 53 private hosted zone"
#   value       = aws_route53_zone.sentinel_private.zone_id
# }

# Route 53 Zone Name Servers
# output "route53_zone_name_servers" {
#   description = "The name servers of the Route 53 private hosted zone"
#   value       = aws_route53_zone.sentinel_private.name_servers
# }

# DNS Gateway URL
# output "dns_gateway_url" {
#   description = "The DNS URL for the gateway proxy"
#   value       = "http://gateway.sentinel.local"
# }

# DNS Backend URL
# output "dns_backend_url" {
#   description = "The DNS URL for the backend service"
#   value       = "http://backend.sentinel.local"
# }

# DNS App URL
# output "dns_app_url" {
#   description = "The DNS URL for the main application"
#   value       = "http://app.sentinel.local"
# }
