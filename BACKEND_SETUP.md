# S3 Backend Setup for Terraform State

This document explains how to set up and use the S3 backend for storing Terraform state files remotely.

## 🚀 Quick Start

### 1. Create the Backend Infrastructure

First, you need to create the S3 bucket that will store your Terraform state:

```bash
# Navigate to the Sentinel project directory
cd /home/shany/Projects/Rapyd/Sentinel

# Initialize and apply the backend configuration
terraform init -backend=false
terraform plan -target=aws_s3_bucket.terraform_state
terraform apply -target=aws_s3_bucket.terraform_state
```

### 2. Initialize with S3 Backend

Once the backend infrastructure is created, initialize Terraform with the S3 backend:

```bash
# Initialize with the S3 backend
terraform init

# Verify the backend configuration
terraform show
```

### 3. Deploy Your Infrastructure

Now you can deploy your main infrastructure:

```bash
# Plan and apply your infrastructure
terraform plan
terraform apply
```

## 📁 File Structure

```
/home/shany/Projects/Rapyd/Sentinel/
├── main.tf              # Main infrastructure configuration with S3 backend
├── backend.tf           # S3 bucket resources (run separately)
├── .github/workflows/   # GitHub Actions workflows
└── BACKEND_SETUP.md     # This documentation
```

## 🔧 Backend Configuration

The S3 backend is configured in `main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "sentinel-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    use_lockfile   = true
  }
}
```

## 🛡️ Security Features

- **Encryption**: State files are encrypted at rest using AES256
- **Versioning**: S3 bucket versioning is enabled for state file history
- **Public Access**: All public access is blocked
- **State Locking**: Local file-based locking prevents concurrent modifications
- **Lifecycle**: Old state versions are automatically cleaned up after 30 days

## 🚨 Important Notes

### Backend Resources Must Exist First
The S3 bucket must exist before you can use the S3 backend. This creates a chicken-and-egg problem that we solve by:

1. Running `backend.tf` first to create the S3 bucket
2. Then using the S3 backend in `main.tf`

### State File Location
- **S3 Bucket**: `sentinel-terraform-state`
- **State File Path**: `infrastructure/terraform.tfstate`
- **Region**: `us-west-2`
- **Locking**: Local file-based locking (use_lockfile = true)

### Cost Considerations
- **S3**: Minimal cost for state storage (typically < $1/month)
- **Locking**: Free local file-based locking
- **Data Transfer**: Free within the same region

## 🔄 Migration from Local State

If you're migrating from local state files:

```bash
# 1. Create the backend infrastructure
terraform init -backend=false
terraform apply -target=aws_s3_bucket.terraform_state

# 2. Migrate your state
terraform init -migrate-state

# 3. Verify the migration
terraform show
```

## 🗑️ Destroying the Backend

⚠️ **WARNING**: Destroying the backend will delete your Terraform state!

```bash
# Use the manual destroy workflow in GitHub Actions
# Or run locally (not recommended for production)
terraform destroy
```

## 🚀 GitHub Actions Integration

The GitHub Actions workflow includes:

- **Manual Deploy**: Deploy to staging or production
- **Manual Destroy**: Destroy infrastructure (requires production environment approval)
- **Automatic Validation**: Format checking and validation on all PRs
- **Automatic Planning**: Plan generation on PRs and pushes

### Manual Destroy via GitHub Actions

1. Go to your repository's Actions tab
2. Select "Terraform CI/CD" workflow
3. Click "Run workflow"
4. Choose:
   - **Action**: `destroy`
   - **Environment**: `production` (will be auto-selected)
5. Click "Run workflow"

## 🔍 Troubleshooting

### Common Issues

1. **Backend Not Found**
   ```bash
   Error: Failed to get existing workspaces
   ```
   **Solution**: Ensure the S3 bucket exists and is accessible

2. **State Lock Error**
   ```bash
   Error: Error acquiring the state lock
   ```
   **Solution**: Check that the S3 bucket exists and IAM permissions are correct

3. **Access Denied**
   ```bash
   Error: Access Denied
   ```
   **Solution**: Verify AWS credentials and IAM permissions

### Debug Commands

```bash
# Check backend configuration
terraform show

# Verify S3 bucket exists
aws s3 ls s3://sentinel-terraform-state

# Verify S3 bucket exists and is accessible
aws s3 ls s3://sentinel-terraform-state

# Check IAM permissions
aws sts get-caller-identity
```

## 📚 Additional Resources

- [Terraform S3 Backend Documentation](https://www.terraform.io/language/settings/backends/s3)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/best-practices.html)
- [Terraform State Management](https://www.terraform.io/language/state)
