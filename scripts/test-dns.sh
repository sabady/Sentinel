#!/bin/bash

# DNS Testing Script for Sentinel Infrastructure
# This script tests DNS resolution across both EKS clusters

set -e

echo "🌐 Sentinel DNS Resolution Test"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to test DNS resolution
test_dns() {
    local cluster_name=$1
    local dns_name=$2
    local expected_type=$3
    
    echo -e "${BLUE}Testing $dns_name on $cluster_name...${NC}"
    
    # Update kubeconfig for the cluster
    aws eks update-kubeconfig --region us-west-2 --name $cluster_name --quiet
    
    # Test DNS resolution
    result=$(kubectl run test-dns-$(date +%s) --image=busybox --rm -i --restart=Never -- nslookup $dns_name 2>/dev/null || echo "FAILED")
    
    if [[ $result == *"$dns_name"* ]]; then
        echo -e "${GREEN}✅ $dns_name resolves successfully on $cluster_name${NC}"
        return 0
    else
        echo -e "${RED}❌ $dns_name failed to resolve on $cluster_name${NC}"
        return 1
    fi
}

# Function to test HTTP connectivity
test_http() {
    local cluster_name=$1
    local url=$2
    
    echo -e "${BLUE}Testing HTTP connectivity to $url on $cluster_name...${NC}"
    
    # Update kubeconfig for the cluster
    aws eks update-kubeconfig --region us-west-2 --name $cluster_name --quiet
    
    # Test HTTP connectivity
    result=$(kubectl run test-http-$(date +%s) --image=busybox --rm -i --restart=Never -- wget -qO- --timeout=10 $url 2>/dev/null || echo "FAILED")
    
    if [[ $result == *"Hello Rapyd"* ]] || [[ $result == *"healthy"* ]]; then
        echo -e "${GREEN}✅ HTTP connectivity to $url successful on $cluster_name${NC}"
        return 0
    else
        echo -e "${RED}❌ HTTP connectivity to $url failed on $cluster_name${NC}"
        return 1
    fi
}

# Function to check Route 53 records
check_route53() {
    echo -e "${BLUE}Checking Route 53 records...${NC}"
    
    # Get the hosted zone ID
    zone_id=$(aws route53 list-hosted-zones --query 'HostedZones[?Name==`sentinel.local.`].Id' --output text | sed 's|/hostedzone/||')
    
    if [ -z "$zone_id" ]; then
        echo -e "${RED}❌ Route 53 hosted zone 'sentinel.local' not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Found Route 53 hosted zone: $zone_id${NC}"
    
    # List DNS records
    echo -e "${BLUE}DNS Records in sentinel.local:${NC}"
    aws route53 list-resource-record-sets --hosted-zone-id $zone_id --query 'ResourceRecordSets[?Type==`A` || Type==`CNAME`].[Name,Type,ResourceRecords[0].Value]' --output table
    
    return 0
}

# Function to check External DNS status
check_external_dns() {
    local cluster_name=$1
    
    echo -e "${BLUE}Checking External DNS status on $cluster_name...${NC}"
    
    # Update kubeconfig for the cluster
    aws eks update-kubeconfig --region us-west-2 --name $cluster_name --quiet
    
    # Check External DNS pod status
    if kubectl get pods -n kube-system -l app=external-dns | grep -q "Running"; then
        echo -e "${GREEN}✅ External DNS is running on $cluster_name${NC}"
        
        # Show External DNS logs (last 10 lines)
        echo -e "${BLUE}External DNS logs (last 10 lines):${NC}"
        kubectl logs -n kube-system deployment/external-dns --tail=10
    else
        echo -e "${RED}❌ External DNS is not running on $cluster_name${NC}"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    echo -e "${YELLOW}Starting DNS resolution tests...${NC}"
    echo ""
    
    # Check Route 53 setup
    check_route53
    echo ""
    
    # Test Gateway EKS cluster
    echo -e "${YELLOW}Testing Gateway EKS Cluster (eks-vpc-gateway)${NC}"
    echo "----------------------------------------"
    
    check_external_dns "eks-vpc-gateway"
    echo ""
    
    test_dns "eks-vpc-gateway" "gateway.sentinel.local" "A"
    test_dns "eks-vpc-gateway" "backend.sentinel.local" "A"
    test_dns "eks-vpc-gateway" "app.sentinel.local" "CNAME"
    echo ""
    
    test_http "eks-vpc-gateway" "http://gateway.sentinel.local/health"
    test_http "eks-vpc-gateway" "http://app.sentinel.local/health"
    echo ""
    
    # Test Backend EKS cluster
    echo -e "${YELLOW}Testing Backend EKS Cluster (eks-vpc-backend)${NC}"
    echo "----------------------------------------"
    
    check_external_dns "eks-vpc-backend"
    echo ""
    
    test_dns "eks-vpc-backend" "gateway.sentinel.local" "A"
    test_dns "eks-vpc-backend" "backend.sentinel.local" "A"
    test_dns "eks-vpc-backend" "app.sentinel.local" "CNAME"
    echo ""
    
    test_http "eks-vpc-backend" "http://backend.sentinel.local/health"
    echo ""
    
    # Summary
    echo -e "${YELLOW}DNS Test Summary${NC}"
    echo "=================="
    echo -e "${GREEN}✅ DNS resolution tests completed${NC}"
    echo -e "${BLUE}💡 If any tests failed, check:${NC}"
    echo "   - Route 53 hosted zone configuration"
    echo "   - External DNS pod status and logs"
    echo "   - VPC peering connection status"
    echo "   - Security group rules"
    echo "   - Service annotations for External DNS"
}

# Run the main function
main "$@"
