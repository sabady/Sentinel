# GitHub OIDC Federation Setup

This guide explains how to set up GitHub OIDC federation for secure AWS deployments without long-lived credentials.

## 🔐 What is GitHub OIDC?

**OpenID Connect (OIDC)** allows GitHub Actions to assume AWS IAM roles using short-lived tokens instead of long-lived access keys. This is much more secure because:

- ✅ **No long-lived credentials** to manage or rotate
- ✅ **Automatic token expiration** (typically 1 hour)
- ✅ **Repository-scoped access** (only your repo can assume the roles)
- ✅ **Audit trail** of all role assumptions
- ✅ **Principle of least privilege** - roles only have needed permissions

## 🏗️ Architecture Overview

```
GitHub Actions → GitHub OIDC Provider → AWS IAM Role → AWS Resources
```

1. **GitHub Actions** requests a token from GitHub's OIDC provider
2. **GitHub OIDC Provider** issues a short-lived JWT token
3. **AWS IAM Role** validates the token and allows role assumption
4. **AWS Resources** are accessed using temporary credentials

## 📋 Prerequisites

- AWS CLI configured with admin permissions (for initial setup)
- GitHub repository with Actions enabled
- Terraform >= 1.0

## 🚀 Setup Steps

### Step 1: Update Repository Information

Edit `variables.tf` and update the GitHub repository:

```hcl
variable "github_repository" {
  description = "GitHub repository in the format 'owner/repo'"
  type        = string
  default     = "your-username/sentinel"  # Update this!
}
```

### Step 2: Deploy OIDC Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the changes
terraform plan

# Apply the OIDC setup
terraform apply
```

This creates:
- GitHub OIDC Identity Provider
- IAM roles for Terraform and EKS operations
- IAM policies with appropriate permissions

### Step 3: Get Role ARNs

After deployment, get the role ARNs:

```bash
# Get Terraform role ARN
terraform output github_actions_terraform_role_arn

# Get EKS role ARN
terraform output github_actions_eks_role_arn

# Get AWS Account ID
terraform output aws_account_id
```

### Step 4: Configure GitHub Secrets

Add these secrets to your GitHub repository:

1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add these secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AWS_TERRAFORM_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-actions-terraform-sentinel` | Role for Terraform operations |
| `AWS_EKS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-actions-eks-sentinel` | Role for EKS operations |

**Example values:**
```
AWS_TERRAFORM_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-terraform-sentinel
AWS_EKS_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-eks-sentinel
```

## 🔧 IAM Roles and Permissions

### Terraform Role (`github-actions-terraform-sentinel`)

**Permissions:**
- S3 access for Terraform state bucket
- EC2 full access (VPC, subnets, security groups, etc.)
- EKS cluster management
- IAM role management
- Route 53 DNS management
- STS GetCallerIdentity

**Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-username/sentinel:*"
        }
      }
    }
  ]
}
```

### EKS Role (`github-actions-eks-sentinel`)

**Permissions:**
- EKS cluster describe and list
- IAM PassRole for EKS service roles

**Trust Policy:**
Same as Terraform role but scoped to EKS operations.

## 🧪 Testing the Setup

### Test 1: Verify OIDC Provider

```bash
# Check if OIDC provider exists
aws iam list-open-id-connect-providers

# Should show:
# {
#   "OpenIDConnectProviderList": [
#     {
#       "Arn": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
#     }
#   ]
# }
```

### Test 2: Verify IAM Roles

```bash
# Check Terraform role
aws iam get-role --role-name github-actions-terraform-sentinel

# Check EKS role
aws iam get-role --role-name github-actions-eks-sentinel
```

### Test 3: Test GitHub Actions

1. Push a change to trigger the workflow
2. Check the Actions tab in GitHub
3. Verify the workflow runs without credential errors

## 🔍 Troubleshooting

### Common Issues

#### 1. "The security token included in the request is invalid"

**Cause:** OIDC provider not properly configured or role ARN incorrect.

**Solution:**
```bash
# Verify OIDC provider thumbprints
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"

# Check role trust policy
aws iam get-role --role-name github-actions-terraform-sentinel --query 'Role.AssumeRolePolicyDocument'
```

#### 2. "User is not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Cause:** Repository name mismatch in trust policy.

**Solution:**
- Verify `github_repository` variable in `variables.tf`
- Ensure GitHub secret `AWS_TERRAFORM_ROLE_ARN` is correct
- Check repository name format: `owner/repo`

#### 3. "Access Denied" errors

**Cause:** Insufficient permissions in IAM policies.

**Solution:**
- Review IAM policies attached to roles
- Add missing permissions if needed
- Use AWS CloudTrail to see what permissions are being denied

### Debug Commands

```bash
# Check OIDC provider configuration
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"

# List all IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `github-actions`)]'

# Check role policies
aws iam list-attached-role-policies --role-name github-actions-terraform-sentinel
aws iam list-role-policies --role-name github-actions-terraform-sentinel

# Test role assumption (from GitHub Actions context)
aws sts assume-role-with-web-identity \
  --role-arn "arn:aws:iam::ACCOUNT_ID:role/github-actions-terraform-sentinel" \
  --role-session-name "test-session" \
  --web-identity-token "YOUR_JWT_TOKEN"
```

## 🔒 Security Best Practices

### 1. Repository Scoping
- Trust policy limits access to your specific repository
- Use `StringLike` condition with `repo:owner/repo:*` pattern

### 2. Environment Restrictions
- Consider adding environment-specific conditions
- Use different roles for different environments

### 3. Permission Minimization
- IAM policies follow principle of least privilege
- Separate roles for different operations (Terraform vs EKS)

### 4. Monitoring
- Enable CloudTrail for audit logging
- Monitor role assumption events
- Set up alerts for unusual activity

## 📊 Cost Impact

**OIDC Setup Costs:**
- **IAM Roles**: Free
- **OIDC Provider**: Free
- **STS Token Exchange**: Free
- **Total**: $0.00/month

**Benefits:**
- No credential management overhead
- Reduced security risk
- Better audit trail
- Automatic token rotation

## 🔄 Migration from Access Keys

### Before (Access Keys)
```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-west-2
```

### After (OIDC)
```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_TERRAFORM_ROLE_ARN }}
    aws-region: us-west-2
    role-session-name: GitHubActions-Terraform
```

## 📚 Additional Resources

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security/hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions AWS Integration](https://github.com/aws-actions/configure-aws-credentials)

## 🎯 Next Steps

1. **Deploy the OIDC infrastructure**
2. **Configure GitHub secrets**
3. **Test the workflow**
4. **Remove old access keys** (if any)
5. **Monitor and audit** role assumptions

Your GitHub Actions will now use secure, short-lived tokens instead of long-lived credentials! 🎉
