#!/bin/bash

# AWS Resource Destruction Script
# This script will destroy all resources in the correct order

set -e

echo "🚨 WARNING: This will destroy ALL resources in your AWS account!"
echo "Account: $(aws sts get-caller-identity --query 'Account' --output text)"
echo "User: $(aws sts get-caller-identity --query 'Arn' --output text)"
echo ""
read -p "Are you sure you want to continue? Type 'YES' to confirm: " confirmation

if [ "$confirmation" != "YES" ]; then
    echo "❌ Destruction cancelled"
    exit 1
fi

echo "🔥 Starting destruction process..."

# Get VPC IDs
VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=sentinel" --query 'Vpcs[*].VpcId' --output text)
echo "📋 Found VPCs: $VPC_IDS"

for VPC_ID in $VPC_IDS; do
    echo "🗑️  Destroying VPC: $VPC_ID"
    
    # Get resources in this VPC
    echo "  🔍 Checking resources in VPC $VPC_ID..."
    
    # 1. Terminate EC2 instances
    INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped,stopping" --query 'Reservations[*].Instances[*].InstanceId' --output text)
    if [ ! -z "$INSTANCES" ]; then
        echo "  🖥️  Terminating instances: $INSTANCES"
        aws ec2 terminate-instances --instance-ids $INSTANCES
        echo "  ⏳ Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids $INSTANCES
    fi
    
    # 2. Delete load balancers
    ELBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text)
    if [ ! -z "$ELBS" ]; then
        echo "  ⚖️  Deleting load balancers: $ELBS"
        for ELB in $ELBS; do
            aws elbv2 delete-load-balancer --load-balancer-arn $ELB
        done
    fi
    
    # 3. Delete NAT gateways
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,running" --query 'NatGateways[*].NatGatewayId' --output text)
    if [ ! -z "$NAT_GATEWAYS" ]; then
        echo "  🌐 Deleting NAT gateways: $NAT_GATEWAYS"
        for NAT in $NAT_GATEWAYS; do
            aws ec2 delete-nat-gateway --nat-gateway-id $NAT
        done
        echo "  ⏳ Waiting for NAT gateways to delete..."
        for NAT in $NAT_GATEWAYS; do
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT
        done
    fi
    
    # 4. Delete elastic IPs
    EIPS=$(aws ec2 describe-addresses --query "Addresses[?InstanceId==null && NetworkInterfaceId==null].AllocationId" --output text)
    if [ ! -z "$EIPS" ]; then
        echo "  🌍 Deleting elastic IPs: $EIPS"
        for EIP in $EIPS; do
            aws ec2 release-address --allocation-id $EIP
        done
    fi
    
    # 5. Delete network interfaces
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
    if [ ! -z "$ENIS" ]; then
        echo "  🔌 Deleting network interfaces: $ENIS"
        for ENI in $ENIS; do
            aws ec2 delete-network-interface --network-interface-id $ENI
        done
    fi
    
    # 6. Delete security groups (except default)
    SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=!default" --query 'SecurityGroups[*].GroupId' --output text)
    if [ ! -z "$SGS" ]; then
        echo "  🛡️  Deleting security groups: $SGS"
        for SG in $SGS; do
            aws ec2 delete-security-group --group-id $SG
        done
    fi
    
    # 7. Delete route tables (except main)
    RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=false" --query 'RouteTables[*].RouteTableId' --output text)
    if [ ! -z "$RTS" ]; then
        echo "  🛣️  Deleting route tables: $RTS"
        for RT in $RTS; do
            aws ec2 delete-route-table --route-table-id $RT
        done
    fi
    
    # 8. Delete subnets
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)
    if [ ! -z "$SUBNETS" ]; then
        echo "  🌐 Deleting subnets: $SUBNETS"
        for SUBNET in $SUBNETS; do
            aws ec2 delete-subnet --subnet-id $SUBNET
        done
    fi
    
    # 9. Delete internet gateways
    IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[*].InternetGatewayId' --output text)
    if [ ! -z "$IGWS" ]; then
        echo "  🌍 Deleting internet gateways: $IGWS"
        for IGW in $IGWS; do
            aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
            aws ec2 delete-internet-gateway --internet-gateway-id $IGW
        done
    fi
    
    # 10. Finally delete the VPC
    echo "  🗑️  Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id $VPC_ID
    echo "  ✅ VPC $VPC_ID deleted successfully"
done

# Delete S3 buckets
echo "🗑️  Deleting S3 buckets..."
S3_BUCKETS=$(aws s3 ls | grep sentinel | awk '{print $3}')
if [ ! -z "$S3_BUCKETS" ]; then
    for BUCKET in $S3_BUCKETS; do
        echo "  🪣 Deleting bucket: $BUCKET"
        aws s3 rb s3://$BUCKET --force
    done
fi

# Delete DynamoDB tables
echo "🗑️  Deleting DynamoDB tables..."
DYNAMO_TABLES=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `sentinel`)]' --output text)
if [ ! -z "$DYNAMO_TABLES" ]; then
    for TABLE in $DYNAMO_TABLES; do
        echo "  📊 Deleting table: $TABLE"
        aws dynamodb delete-table --table-name $TABLE
    done
fi

echo "🎉 Destruction complete!"
echo "⚠️  Note: Some resources may take time to fully delete"
echo "🔍 Check AWS Console to verify all resources are gone"

