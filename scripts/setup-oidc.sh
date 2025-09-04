#!/bin/bash

# GitHub OIDC Setup Script for Sentinel Infrastructure
# This script helps set up GitHub OIDC federation for secure AWS deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔐 GitHub OIDC Federation Setup${NC}"
echo "=================================="

# Function to check if AWS CLI is configured
check_aws_cli() {
    echo -e "${BLUE}Checking AWS CLI configuration...${NC}"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is not installed${NC}"
        echo "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is not configured${NC}"
        echo "Please run: aws configure"
        exit 1
    fi
    
    echo -e "${GREEN}✅ AWS CLI is configured${NC}"
}

# Function to get current AWS account ID
get_account_id() {
    echo -e "${BLUE}Getting AWS Account ID...${NC}"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✅ AWS Account ID: $ACCOUNT_ID${NC}"
}

# Function to check if Terraform is installed
check_terraform() {
    echo -e "${BLUE}Checking Terraform installation...${NC}"
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ Terraform is not installed${NC}"
        echo "Please install Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Terraform is installed${NC}"
}

# Function to validate GitHub repository format
validate_github_repo() {
    echo -e "${BLUE}Validating GitHub repository configuration...${NC}"
    
    if [ ! -f "variables.tf" ]; then
        echo -e "${RED}❌ variables.tf not found${NC}"
        exit 1
    fi
    
    # Check if github_repository is set to default value
    if grep -q "your-username/sentinel" variables.tf; then
        echo -e "${YELLOW}⚠️  Please update the GitHub repository in variables.tf${NC}"
        echo "Edit variables.tf and change:"
        echo "  default = \"your-username/sentinel\""
        echo "To:"
        echo "  default = \"your-actual-username/sentinel\""
        echo ""
        read -p "Press Enter after updating variables.tf..."
    fi
    
    echo -e "${GREEN}✅ GitHub repository configuration validated${NC}"
}

# Function to deploy OIDC infrastructure
deploy_oidc() {
    echo -e "${BLUE}Deploying OIDC infrastructure...${NC}"
    
    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        echo -e "${BLUE}Initializing Terraform...${NC}"
        terraform init
    fi
    
    # Plan the deployment
    echo -e "${BLUE}Planning OIDC deployment...${NC}"
    terraform plan -target=aws_iam_openid_connect_provider.github \
                   -target=aws_iam_role.github_actions_terraform \
                   -target=aws_iam_role.github_actions_eks \
                   -target=aws_iam_policy.github_actions_terraform \
                   -target=aws_iam_policy.github_actions_eks \
                   -target=aws_iam_role_policy_attachment.github_actions_terraform \
                   -target=aws_iam_role_policy_attachment.github_actions_eks
    
    echo ""
    read -p "Do you want to apply these changes? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Applying OIDC infrastructure...${NC}"
        terraform apply -target=aws_iam_openid_connect_provider.github \
                        -target=aws_iam_role.github_actions_terraform \
                        -target=aws_iam_role.github_actions_eks \
                        -target=aws_iam_policy.github_actions_terraform \
                        -target=aws_iam_policy.github_actions_eks \
                        -target=aws_iam_role_policy_attachment.github_actions_terraform \
                        -target=aws_iam_role_policy_attachment.github_actions_eks \
                        -auto-approve
        
        echo -e "${GREEN}✅ OIDC infrastructure deployed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Deployment cancelled${NC}"
        exit 0
    fi
}

# Function to get role ARNs
get_role_arns() {
    echo -e "${BLUE}Getting IAM Role ARNs...${NC}"
    
    TERRAFORM_ROLE_ARN=$(terraform output -raw github_actions_terraform_role_arn 2>/dev/null || echo "")
    EKS_ROLE_ARN=$(terraform output -raw github_actions_eks_role_arn 2>/dev/null || echo "")
    
    if [ -z "$TERRAFORM_ROLE_ARN" ] || [ -z "$EKS_ROLE_ARN" ]; then
        echo -e "${RED}❌ Could not get role ARNs${NC}"
        echo "Make sure the OIDC infrastructure is deployed"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Role ARNs retrieved${NC}"
    echo ""
    echo -e "${YELLOW}📋 GitHub Secrets to Configure:${NC}"
    echo "=================================="
    echo ""
    echo -e "${BLUE}AWS_TERRAFORM_ROLE_ARN${NC}"
    echo "$TERRAFORM_ROLE_ARN"
    echo ""
    echo -e "${BLUE}AWS_EKS_ROLE_ARN${NC}"
    echo "$EKS_ROLE_ARN"
    echo ""
    echo -e "${BLUE}AWS_ACCOUNT_ID${NC}"
    echo "$ACCOUNT_ID"
    echo ""
}

# Function to verify OIDC setup
verify_oidc() {
    echo -e "${BLUE}Verifying OIDC setup...${NC}"
    
    # Check OIDC provider
    if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `token.actions.githubusercontent.com`)]' --output text | grep -q "arn:aws:iam"; then
        echo -e "${GREEN}✅ GitHub OIDC Provider exists${NC}"
    else
        echo -e "${RED}❌ GitHub OIDC Provider not found${NC}"
        return 1
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name github-actions-terraform-sentinel &> /dev/null; then
        echo -e "${GREEN}✅ Terraform IAM Role exists${NC}"
    else
        echo -e "${RED}❌ Terraform IAM Role not found${NC}"
        return 1
    fi
    
    if aws iam get-role --role-name github-actions-eks-sentinel &> /dev/null; then
        echo -e "${GREEN}✅ EKS IAM Role exists${NC}"
    else
        echo -e "${RED}❌ EKS IAM Role not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ OIDC setup verification completed${NC}"
}

# Function to show next steps
show_next_steps() {
    echo ""
    echo -e "${YELLOW}🎯 Next Steps:${NC}"
    echo "=============="
    echo ""
    echo "1. 📝 Configure GitHub Secrets:"
    echo "   Go to your repository → Settings → Secrets and variables → Actions"
    echo "   Add the secrets shown above"
    echo ""
    echo "2. 🧪 Test the Setup:"
    echo "   Push a change to trigger GitHub Actions"
    echo "   Check the Actions tab for successful runs"
    echo ""
    echo "3. 🔒 Remove Old Credentials (if any):"
    echo "   Delete any existing AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets"
    echo ""
    echo "4. 📚 Read the Documentation:"
    echo "   Check OIDC_SETUP.md for detailed information"
    echo ""
    echo -e "${GREEN}🎉 OIDC setup completed successfully!${NC}"
}

# Main execution
main() {
    check_aws_cli
    get_account_id
    check_terraform
    validate_github_repo
    deploy_oidc
    get_role_arns
    verify_oidc
    show_next_steps
}

# Run the main function
main "$@"
