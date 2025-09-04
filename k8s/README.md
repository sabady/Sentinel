# Kubernetes Applications

This directory contains Kubernetes manifests for deploying applications to the Sentinel EKS clusters.

## Architecture

- **Gateway EKS Cluster** (`eks-vpc-gateway`): Hosts the proxy application with a public LoadBalancer
- **Backend EKS Cluster** (`eks-vpc-backend`): Hosts the "Hello Rapyd" web application

## Applications

### Backend Application (`k8s/backend/`)

**Purpose**: Simple web application displaying "Hello Rapyd"

**Components**:
- **Deployment**: `hello-rapyd-backend` - Nginx container serving the web page
- **Service**: `hello-rapyd-backend-service` - ClusterIP service for internal access
- **ConfigMaps**: 
  - `hello-rapyd-config` - Nginx configuration
  - `hello-rapyd-html` - HTML content with "Hello Rapyd" page

**Features**:
- Beautiful gradient background with modern UI
- Health check endpoint at `/health`
- Resource limits and requests configured
- 2 replicas for high availability

### Gateway Proxy (`k8s/gateway/`)

**Purpose**: Proxy application that forwards traffic to the backend service

**Components**:
- **Deployment**: `sentinel-proxy` - Nginx proxy container
- **Services**: 
  - `sentinel-proxy-service` - ClusterIP service for internal access
  - `sentinel-proxy-loadbalancer` - LoadBalancer service for public access
- **ConfigMaps**:
  - `sentinel-proxy-config` - Nginx proxy configuration
  - `sentinel-proxy-html` - Custom error page for service unavailability

**Features**:
- LoadBalancer service for public internet access
- Upstream configuration pointing to backend service
- Health check endpoint at `/health`
- Error handling with custom 50x error pages
- Timeout and retry configurations
- Resource limits and requests configured
- 2 replicas for high availability

## Network Flow

```
Internet → LoadBalancer → Gateway EKS → Proxy Pod → Backend Service (via VPC peering) → Backend EKS → Backend Pod
```

1. **Public Access**: Internet traffic hits the LoadBalancer service
2. **Gateway Processing**: LoadBalancer routes to proxy pods in Gateway EKS
3. **VPC Communication**: Proxy forwards requests to backend service via VPC peering
4. **Backend Response**: Backend service responds with "Hello Rapyd" page

## Deployment

Applications are automatically deployed via GitHub Actions when:
- Pushing to `main` branch (production)
- Pushing to `develop` branch (staging)
- Manual workflow dispatch

### Manual Deployment

To deploy manually:

```bash
# Deploy backend application
kubectl config use-context <backend-eks-context>
kubectl apply -f k8s/backend/deployment.yaml

# Deploy proxy application
kubectl config use-context <gateway-eks-context>
kubectl apply -f k8s/gateway/deployment.yaml
```

### Verification

```bash
# Check backend deployment
kubectl get pods -l app=hello-rapyd-backend
kubectl get services

# Check proxy deployment
kubectl get pods -l app=sentinel-proxy
kubectl get services
kubectl get service sentinel-proxy-loadbalancer

# Get LoadBalancer external IP
kubectl get service sentinel-proxy-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Accessing the Application

1. **Get LoadBalancer URL**:
   ```bash
   kubectl get service sentinel-proxy-loadbalancer
   ```

2. **Access via browser**: `http://<EXTERNAL-IP>`

3. **Expected Result**: Beautiful "Hello Rapyd" page with gradient background

## Troubleshooting

### Backend Issues
```bash
# Check backend pods
kubectl describe pods -l app=hello-rapyd-backend

# Check backend logs
kubectl logs -l app=hello-rapyd-backend

# Test backend service internally
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://hello-rapyd-backend-service
```

### Proxy Issues
```bash
# Check proxy pods
kubectl describe pods -l app=sentinel-proxy

# Check proxy logs
kubectl logs -l app=sentinel-proxy

# Test proxy health
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://sentinel-proxy-service/health
```

### Network Issues
```bash
# Verify VPC peering
aws ec2 describe-vpc-peering-connections --filters "Name=tag:Project,Values=sentinel"

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:Project,Values=sentinel"
```

## Security Considerations

- Backend service is only accessible via VPC peering (no direct internet access)
- Proxy service has public LoadBalancer but forwards to private backend
- Security groups control traffic flow between VPCs
- All pods have resource limits configured
- Health checks ensure service availability
