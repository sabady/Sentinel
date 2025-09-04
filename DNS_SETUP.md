# DNS Resolution Setup for Sentinel

This guide explains how DNS resolution is configured for the Sentinel infrastructure.

## 🌐 DNS Architecture Overview

### Components
1. **Route 53 Private Hosted Zone**: `sentinel.local`
2. **External DNS**: Automatic DNS record management
3. **VPC DNS Resolution**: Cross-VPC DNS resolution via peering

### DNS Names
- **Gateway Service**: `gateway.sentinel.local`
- **Backend Service**: `backend.sentinel.local`
- **Main Application**: `app.sentinel.local` (CNAME to gateway)

## 🏗️ Infrastructure Components

### Route 53 Private Hosted Zone
```hcl
resource "aws_route53_zone" "sentinel_private" {
  name = "sentinel.local"
  
  vpc {
    vpc_id = module.vpc["vpc_gateway"].vpc_id
  }
  
  vpc {
    vpc_id = module.vpc["vpc_backend"].vpc_id
  }
}
```

### DNS Records
- **A Records**: Direct IP mappings for services
- **CNAME Records**: Aliases for easy access
- **TTL**: 300 seconds (5 minutes) for quick updates

## 🚀 Deployment Process

### 1. Infrastructure Deployment
```bash
terraform apply
```

This creates:
- Route 53 private hosted zone
- DNS records (with placeholder IPs)
- VPC associations

### 2. External DNS Deployment
External DNS is automatically deployed to both EKS clusters and:
- Monitors Kubernetes services with DNS annotations
- Creates/updates Route 53 records automatically
- Manages DNS record lifecycle

### 3. Service Deployment
Services are deployed with DNS annotations:
```yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: gateway.sentinel.local
    external-dns.alpha.kubernetes.io/ttl: "300"
```

## 🔧 Configuration Details

### External DNS Configuration
- **Source**: Kubernetes services and ingresses
- **Provider**: AWS Route 53
- **Zone Type**: Private hosted zones
- **Domain Filter**: `sentinel.local`
- **Registry**: TXT records for ownership tracking

### VPC DNS Settings
Both VPCs have DNS support enabled:
- `enable_dns_hostnames = true`
- `enable_dns_support = true`

### Cross-VPC Resolution
DNS resolution works across VPCs because:
1. Both VPCs are associated with the same Route 53 private hosted zone
2. VPC peering allows cross-VPC communication
3. Route tables include routes for the peered VPC CIDR blocks

## 📋 DNS Records Created

### Automatic Records (via External DNS)
- `gateway.sentinel.local` → LoadBalancer IP
- `backend.sentinel.local` → Backend service IP

### Manual Records (via Terraform)
- `app.sentinel.local` → CNAME to `gateway.sentinel.local`

## 🧪 Testing DNS Resolution

### From Gateway EKS Pods
```bash
# Test backend resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup backend.sentinel.local

# Test gateway resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup gateway.sentinel.local
```

### From Backend EKS Pods
```bash
# Test gateway resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup gateway.sentinel.local

# Test app resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup app.sentinel.local
```

### From EC2 Instances (if any)
```bash
# Test all DNS names
nslookup gateway.sentinel.local
nslookup backend.sentinel.local
nslookup app.sentinel.local
```

## 🔍 Troubleshooting

### Check Route 53 Zone
```bash
aws route53 list-hosted-zones --query 'HostedZones[?Name==`sentinel.local.`]'
```

### Check DNS Records
```bash
aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID>
```

### Check External DNS Logs
```bash
kubectl logs -n kube-system deployment/external-dns
```

### Verify VPC Associations
```bash
aws route53 get-hosted-zone --id <ZONE_ID> --query 'VPCs'
```

### Test DNS Resolution
```bash
# From within VPC
dig gateway.sentinel.local
dig backend.sentinel.local
dig app.sentinel.local
```

## 🛠️ Manual DNS Management

### Add Custom DNS Record
```bash
# Create a new A record
aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "custom.sentinel.local",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "10.0.1.100"}]
    }
  }]
}'
```

### Update Existing Record
```bash
# Update an A record
aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> --change-batch '{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "gateway.sentinel.local",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "NEW_IP_ADDRESS"}]
    }
  }]
}'
```

## 💰 Cost Considerations

### Route 53 Costs
- **Private Hosted Zone**: ~$0.50/month
- **DNS Queries**: $0.40 per million queries
- **Health Checks**: $0.50/month per health check (if used)

### Estimated Monthly Cost
- **Basic Setup**: ~$1.00/month
- **With Health Checks**: ~$2.00/month

## 🔒 Security Considerations

### DNS Security
- Private hosted zones are only accessible from associated VPCs
- No public DNS exposure
- TXT records track External DNS ownership

### Access Control
- External DNS uses IAM roles for Route 53 access
- Minimal required permissions
- No cross-account access

## 📚 Additional Resources

### AWS Documentation
- [Route 53 Private Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html)
- [VPC DNS Resolution](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html)

### External DNS Documentation
- [External DNS GitHub](https://github.com/kubernetes-sigs/external-dns)
- [AWS Provider Configuration](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)

### Kubernetes DNS
- [Kubernetes DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [CoreDNS Configuration](https://coredns.io/plugins/kubernetes/)
