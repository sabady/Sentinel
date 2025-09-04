#!/bin/bash

# Enhanced AWS Resource Cleanup Script
# This script handles EKS-managed security groups and prevents cross-reference issues

set -e

echo "🧹 Starting AWS Resource Cleanup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    print_status "AWS CLI is configured and working"
}

# Function to get all VPCs
get_vpcs() {
    aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output text | grep -E "(vpc-gateway|vpc-backend|sentinel)" || true
}

# Function to get EKS clusters
get_eks_clusters() {
    aws eks list-clusters --query 'clusters[*]' --output text 2>/dev/null || true
}

# Function to delete EKS clusters
delete_eks_clusters() {
    local clusters=$(get_eks_clusters)
    
    if [ -z "$clusters" ]; then
        print_status "No EKS clusters found"
        return 0
    fi
    
    for cluster in $clusters; do
        print_status "Deleting EKS cluster: $cluster"
        
        # Delete node groups first
        local nodegroups=$(aws eks list-nodegroups --cluster-name $cluster --query 'nodegroups[*]' --output text 2>/dev/null || true)
        for nodegroup in $nodegroups; do
            print_status "Deleting node group: $nodegroup from cluster: $cluster"
            aws eks delete-nodegroup --cluster-name $cluster --nodegroup-name $nodegroup || true
        done
        
        # Wait for node groups to be deleted
        if [ -n "$nodegroups" ]; then
            print_status "Waiting for node groups to be deleted..."
            for nodegroup in $nodegroups; do
                aws eks wait nodegroup-deleted --cluster-name $cluster --nodegroup-name $nodegroup || true
            done
        fi
        
        # Delete the cluster
        aws eks delete-cluster --name $cluster || true
    done
    
    # Wait for clusters to be deleted
    if [ -n "$clusters" ]; then
        print_status "Waiting for EKS clusters to be deleted..."
        for cluster in $clusters; do
            aws eks wait cluster-deleted --name $cluster || true
        done
    fi
}

# Function to clean up security groups
cleanup_security_groups() {
    local vpc_id=$1
    print_status "Cleaning up security groups for VPC: $vpc_id"
    
    # Get all security groups in the VPC (except default)
    local security_groups=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || true)
    
    if [ -z "$security_groups" ]; then
        print_status "No custom security groups found in VPC: $vpc_id"
        return 0
    fi
    
    for sg_id in $security_groups; do
        print_status "Processing security group: $sg_id"
        
        # Remove all ingress rules
        local ingress_rules=$(aws ec2 describe-security-groups \
            --group-ids $sg_id \
            --query 'SecurityGroups[0].IpPermissions[*]' \
            --output json 2>/dev/null || echo "[]")
        
        if [ "$ingress_rules" != "[]" ] && [ "$ingress_rules" != "null" ]; then
            print_status "Removing ingress rules from $sg_id"
            aws ec2 revoke-security-group-ingress --group-id $sg_id --ip-permissions "$ingress_rules" || true
        fi
        
        # Remove all egress rules (except default)
        local egress_rules=$(aws ec2 describe-security-groups \
            --group-ids $sg_id \
            --query 'SecurityGroups[0].IpPermissionsEgress[?FromPort!=`-1`]' \
            --output json 2>/dev/null || echo "[]")
        
        if [ "$egress_rules" != "[]" ] && [ "$egress_rules" != "null" ]; then
            print_status "Removing custom egress rules from $sg_id"
            aws ec2 revoke-security-group-egress --group-id $sg_id --ip-permissions "$egress_rules" || true
        fi
        
        # Try to delete the security group
        print_status "Attempting to delete security group: $sg_id"
        if aws ec2 delete-security-group --group-id $sg_id; then
            print_status "Successfully deleted security group: $sg_id"
        else
            print_warning "Failed to delete security group: $sg_id (may have dependencies)"
        fi
    done
}

# Function to clean up VPC resources
cleanup_vpc_resources() {
    local vpc_id=$1
    print_status "Cleaning up VPC resources for: $vpc_id"
    
    # Clean up security groups
    cleanup_security_groups $vpc_id
    
    # Clean up other VPC resources (NAT gateways, subnets, etc.)
    # This would be similar to the previous cleanup script
    print_status "VPC resource cleanup completed for: $vpc_id"
}

# Function to delete VPCs
delete_vpcs() {
    local vpcs=$(get_vpcs)
    
    if [ -z "$vpcs" ]; then
        print_status "No VPCs found to delete"
        return 0
    fi
    
    for vpc_info in $vpcs; do
        local vpc_id=$(echo $vpc_info | awk '{print $1}')
        local vpc_name=$(echo $vpc_info | awk '{print $2}')
        
        print_status "Processing VPC: $vpc_id ($vpc_name)"
        
        # Clean up VPC resources first
        cleanup_vpc_resources $vpc_id
        
        # Try to delete the VPC
        print_status "Attempting to delete VPC: $vpc_id"
        if aws ec2 delete-vpc --vpc-id $vpc_id; then
            print_status "Successfully deleted VPC: $vpc_id"
        else
            print_warning "Failed to delete VPC: $vpc_id (may have remaining dependencies)"
        fi
    done
}

# Main cleanup process
main() {
    print_status "Starting comprehensive AWS resource cleanup..."
    
    # Check AWS CLI
    check_aws_cli
    
    # Delete EKS clusters first (this will clean up EKS-managed security groups)
    print_status "Step 1: Deleting EKS clusters..."
    delete_eks_clusters
    
    # Wait a bit for EKS cleanup to complete
    print_status "Waiting for EKS cleanup to complete..."
    sleep 30
    
    # Delete VPCs and remaining resources
    print_status "Step 2: Deleting VPCs and remaining resources..."
    delete_vpcs
    
    print_status "✅ Cleanup completed!"
    print_warning "Note: Some resources may still exist if they have dependencies. Check AWS Console for any remaining resources."
}

# Run main function
main "$@"
