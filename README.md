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
- Route 53 private hosted zones for DNS resolution
- External DNS for automatic DNS record management

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

### Applications
- **Backend Service**: "Hello Rapyd" web application in backend EKS
- **Gateway Proxy**: Nginx proxy with LoadBalancer in gateway EKS
- **DNS Resolution**: Cross-VPC DNS resolution via Route 53

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl for EKS cluster management
- GitHub repository with Actions enabled

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

1. **Run the setup script**:
   ```bash
   ./scripts/setup-oidc.sh
   ```

2. **Configure GitHub secrets** with the role ARNs provided by the script

#### Required Secrets (Temporary - Access Keys)

**Note**: OIDC federation is temporarily disabled due to IAM permission restrictions. Using access keys for now.

Add these secrets to your GitHub repository:

1. **AWS_ACCESS_KEY_ID**: AWS access key with appropriate permissions
2. **AWS_SECRET_ACCESS_KEY**: AWS secret access key

### Future: OIDC Federation Setup

Once IAM permissions are available, you can switch to OIDC federation:

1. **AWS_TERRAFORM_ROLE_ARN**: IAM role ARN for Terraform operations
2. **AWS_EKS_ROLE_ARN**: IAM role ARN for EKS operations

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

## Applications and DNS

### Deployed Applications
- **Backend**: "Hello Rapyd" web application accessible via `backend.sentinel.local`
- **Gateway**: Nginx proxy accessible via `gateway.sentinel.local` and public LoadBalancer
- **Main App**: Accessible via `app.sentinel.local` (CNAME to gateway)

### DNS Resolution
- **Private DNS Zone**: `sentinel.local` for internal VPC communication
- **External DNS**: Automatically manages DNS records from Kubernetes services
- **Cross-VPC Resolution**: Services can resolve each other via DNS names

### Accessing Applications
```bash
# Get LoadBalancer external IP
kubectl get service sentinel-proxy-loadbalancer

# Access via browser
http://<EXTERNAL-IP>
```

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

## Scripts and Documentation

### Available Scripts
- **`scripts/setup-oidc.sh`**: Automated OIDC setup and configuration
- **`scripts/test-dns.sh`**: Comprehensive DNS resolution testing
- **`destroy_all.sh`**: Complete infrastructure cleanup

### Documentation
- **`OIDC_SETUP.md`**: Detailed GitHub OIDC federation guide
- **`DNS_SETUP.md`**: DNS resolution configuration and troubleshooting
- **`BACKEND_SETUP.md`**: S3 backend setup instructions
- **`k8s/README.md`**: Kubernetes applications documentation

## Troubleshooting

### Common Issues
1. **VPC Peering**: Ensure route tables are properly configured
2. **Security Groups**: EKS now manages security groups automatically to prevent cross-reference issues
3. **NAT Gateway**: Check public subnet and internet gateway configuration
4. **EKS**: Verify security group associations and subnet configurations
5. **OIDC**: Check GitHub repository name in `variables.tf`
6. **DNS**: Verify Route 53 private hosted zone configuration
7. **Resource Cleanup**: Use the enhanced cleanup script to prevent cross-reference issues

### Cleanup Scripts

If you need to manually clean up AWS resources:

```bash
# Use the enhanced cleanup script
./scripts/cleanup-aws-resources.sh
```

This script handles EKS-managed security groups and prevents cross-reference issues that previously prevented VPC deletion.

### Debugging Commands
```bash
# Check VPC peering status
aws ec2 describe-vpc-peering-connections

# Verify security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# Check EKS cluster status
aws eks describe-cluster --name eks-vpc-gateway --region us-west-2

# Test DNS resolution
./scripts/test-dns.sh

# Check OIDC setup
./scripts/setup-oidc.sh
```

## Contributing

1. Create a feature branch from `main`
2. Make changes and test locally
3. Create a pull request
4. Ensure all checks pass
5. Merge after review

## License

This project is licensed under the MIT License.
