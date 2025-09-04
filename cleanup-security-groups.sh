#!/bin/bash

# Clean up EKS security groups that are preventing VPC deletion

echo "Cleaning up EKS security groups..."

# Gateway VPC security groups (first set - already deleted)
# GATEWAY_NODE_SG="sg-0c495bb3c9c082542"
# GATEWAY_CLUSTER_SG="sg-07c2299a7542e8007"

# Backend VPC security groups (first set - already deleted)
# BACKEND_NODE_SG="sg-014df22c0a650377f"
# BACKEND_CLUSTER_SG="sg-050cd76e1491de52c"

# Additional Gateway VPC security groups
GATEWAY_NODE_SG2="sg-0084fa74158dcfe3f"
GATEWAY_CLUSTER_SG2="sg-09ffdc5f003710e16"

# Additional Backend VPC security groups
BACKEND_NODE_SG2="sg-000cc5bd10eb44a46"
BACKEND_CLUSTER_SG2="sg-0ef013fe4f500d298"

# Function to remove all ingress rules from a security group
remove_all_ingress_rules() {
    local sg_id=$1
    echo "Removing all ingress rules from $sg_id..."
    
    # Get all ingress rules
    local rules=$(aws ec2 describe-security-groups --group-ids $sg_id --query 'SecurityGroups[0].IpPermissions[*]' --output json)
    
    if [ "$rules" != "[]" ] && [ "$rules" != "null" ]; then
        echo "Rules found, removing them..."
        aws ec2 revoke-security-group-ingress --group-id $sg_id --ip-permissions "$rules"
    else
        echo "No ingress rules found"
    fi
}

# Function to remove all egress rules from a security group
remove_all_egress_rules() {
    local sg_id=$1
    echo "Removing all egress rules from $sg_id..."
    
    # Get all egress rules
    local rules=$(aws ec2 describe-security-groups --group-ids $sg_id --query 'SecurityGroups[0].IpPermissionsEgress[*]' --output json)
    
    if [ "$rules" != "[]" ] && [ "$rules" != "null" ]; then
        echo "Egress rules found, removing them..."
        aws ec2 revoke-security-group-egress --group-id $sg_id --ip-permissions "$rules"
    else
        echo "No egress rules found"
    fi
}

# Remove rules from additional gateway security groups
echo "Processing Additional Gateway VPC security groups..."
remove_all_ingress_rules $GATEWAY_NODE_SG2
remove_all_egress_rules $GATEWAY_NODE_SG2
remove_all_ingress_rules $GATEWAY_CLUSTER_SG2
remove_all_egress_rules $GATEWAY_CLUSTER_SG2

# Remove rules from additional backend security groups
echo "Processing Additional Backend VPC security groups..."
remove_all_ingress_rules $BACKEND_NODE_SG2
remove_all_egress_rules $BACKEND_NODE_SG2
remove_all_ingress_rules $BACKEND_CLUSTER_SG2
remove_all_egress_rules $BACKEND_CLUSTER_SG2

# Now try to delete the security groups
echo "Attempting to delete security groups..."

for sg in $GATEWAY_NODE_SG2 $GATEWAY_CLUSTER_SG2 $BACKEND_NODE_SG2 $BACKEND_CLUSTER_SG2; do
    echo "Deleting security group $sg..."
    if aws ec2 delete-security-group --group-id $sg; then
        echo "Successfully deleted $sg"
    else
        echo "Failed to delete $sg"
    fi
done

echo "Security group cleanup completed!"
