# Sentinel Infrastructure

This repository contains Terraform configuration for a multi-VPC AWS infrastructure with EKS clusters, designed for a gateway-to-backend architecture.

## Architecture Overview

### VPCs
- **VPC Gateway** (`10.0.0.0/16`): Internet-facing VPC with public access on port 80
- **VPC Backend** (`10.1.0.0/16`): Private VPC accessible only from gateway VPC on port 80

### EKS Clusters
- **eks-vpc-gateway**: Public-facing Kubernetes cluster
- **eks-vpc-backend**: Private Kubernetes cluster

### Networking
- VPC peering between gateway and backend VPCs
- NAT Gateways for internet access from private subnets
- Security groups with proper access controls

## Infrastructure Components

### VPC Configuration
- 2 Availability Zones (us-west-2a, us-west-2b)
- Private subnets for EKS clusters
- Public subnets for NAT Gateways
- Single NAT Gateway per VPC for cost optimization

### EKS Configuration
- Kubernetes version: 1.31
- Node groups: t4g.medium spot instances
- Auto-scaling: 1-3 nodes with 2 desired nodes
- ARM64 architecture (Graviton2) for cost efficiency

### Security Groups
- **Gateway VPC**: Accepts HTTP traffic from internet
- **Backend VPC**: Accepts HTTP traffic from gateway VPC only
- **Both VPCs**: Full Kubernetes internal communication support

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl for EKS cluster management

## Local Development

### Initialize Terraform
```bash
terraform init
```

### Plan Changes
```bash
terraform plan
```

### Apply Changes
```bash
terraform apply
```

### Destroy Infrastructure
```bash
terraform destroy
```

## GitHub Actions Setup

### OIDC Federation (Recommended)

This project uses **GitHub OIDC federation** for secure AWS deployments without long-lived credentials.

#### Quick Setup

1. **Update repository information** in `variables.tf`:
   ```hcl
   variable "github_repository" {
     default = "your-username/sentinel"  # Update this!
   }
   ```

2. **Run the setup script**:
   ```bash
   ./scripts/setup-oidc.sh
   ```

3. **Configure GitHub secrets** with the role ARNs provided by the script

#### Required Secrets (OIDC)

Add these secrets to your GitHub repository:

1. **AWS_TERRAFORM_ROLE_ARN**: IAM role ARN for Terraform operations
2. **AWS_EKS_ROLE_ARN**: IAM role ARN for EKS operations

### Legacy Setup (Access Keys)

If you prefer to use access keys instead of OIDC:

1. **AWS_ACCESS_KEY_ID**: AWS access key with appropriate permissions
2. **AWS_SECRET_ACCESS_KEY**: AWS secret access key

### Workflow Triggers

- **Push to main**: Automatically applies changes to production
- **Pull Request**: Runs verification and planning
- **Manual Dispatch**: Allows manual deployment to production

### Workflow Jobs

1. **terraform-verify**: Format check, init, and validation
2. **terraform-plan**: Creates and uploads execution plan (PR only)
3. **terraform-apply**: Applies changes to production (main branch only)
4. **terraform-apply-manual**: Manual deployment to production
5. **deploy-backend-app**: Deploys backend application to EKS clusters
6. **terraform-destroy**: Manual infrastructure destruction

## Security Considerations

- VPC peering provides secure cross-VPC communication
- Security groups restrict access to necessary ports only
- Backend VPC is not directly accessible from internet
- EKS clusters use private subnets with NAT Gateway access

## Cost Optimization

- Spot instances for worker nodes (60-90% cost savings)
- Single NAT Gateway per VPC
- ARM64 instances (t4g.medium) for better price/performance
- Auto-scaling node groups

## Monitoring and Maintenance

### EKS Cluster Management
```bash
# Configure kubectl for gateway cluster
aws eks update-kubeconfig --region us-west-2 --name eks-vpc-gateway

# Configure kubectl for backend cluster
aws eks update-kubeconfig --region us-west-2 --name eks-vpc-backend
```

### Node Group Scaling
- Automatic scaling based on demand (1-3 nodes)
- Spot instance interruption handling
- Health checks and replacement

## Troubleshooting

### Common Issues
1. **VPC Peering**: Ensure route tables are properly configured
2. **Security Groups**: Verify ingress/egress rules match requirements
3. **NAT Gateway**: Check public subnet and internet gateway configuration
4. **EKS**: Verify security group associations and subnet configurations

### Debugging Commands
```bash
# Check VPC peering status
aws ec2 describe-vpc-peering-connections

# Verify security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# Check EKS cluster status
aws eks describe-cluster --name eks-vpc-gateway --region us-west-2
```

## Contributing

1. Create a feature branch from `develop`
2. Make changes and test locally
3. Create a pull request
4. Ensure all checks pass
5. Merge after review

## License

This project is licensed under the MIT License.
