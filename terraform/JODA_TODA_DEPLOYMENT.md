# Joda-Toda PrivateLink Deployment Guide

## Overview

This guide walks through deploying AWS PrivateLink to provide Joda-Toda-AWS account access to on-premises Redis servers.

## Architecture

- **Provider Account**: **Prod Account** (creates NLB and Endpoint Service)
  - **IMPORTANT**: Connectivity Account remains untouched - all changes in Prod Account
- **Consumer Account**: Joda-Toda-AWS Account (creates VPC Endpoints in Dev VPC only)

## Prerequisites

### Prod Account
- AWS CLI configured with Prod Account credentials
- Prod VPC ID (10.2.0.0/16)
- Subnets in Prod VPC that can reach on-premises via Transit Gateway
- On-premises Redis server IPs (routable via TGW → Connectivity Account → Direct Connect)
- Joda-Toda-AWS account ID
- Route tables configured to allow traffic to on-premises (10.0.0.0/16) via TGW

### Joda-Toda-AWS Account
- AWS CLI configured with Joda-Toda-AWS account credentials
- Dev VPC ID (10.3.0.0/16)
- At least 2 subnets in Dev VPC (different AZs for HA)

## Deployment Steps

### Step 1: Deploy Prod Account Infrastructure

**IMPORTANT**: No changes to Connectivity Account - everything deployed from Prod Account.

```bash
cd terraform/prod-account

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region = "us-east-1"
prod_vpc_id = "vpc-xxxxxxxxx"  # Prod VPC ID (10.2.0.0/16)
prod_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]  # Subnets in Prod VPC
redis_server_ips = ["10.0.4.10", "10.0.4.11", "10.0.4.12"]  # On-prem Redis IPs
redis_port = 6379
consumer_account_id = "123456789012"  # Joda-Toda-AWS account ID
endpoint_service_name = "joda-redis-onprem-service"
EOF

# Initialize and plan
terraform init
terraform plan

# Apply
terraform apply
```

**Important**: Save the `vpc_endpoint_service_name` output value. You'll need it for Step 2.

Example output:
```
vpc_endpoint_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef"
```

### Step 2: Deploy Joda-Toda-AWS Account Infrastructure

```bash
cd terraform/joda-toda-account

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region = "us-east-1"
dev_vpc_id = "vpc-zzzzzzzzz"  # Dev VPC ID in Joda-Toda-AWS account
dev_subnet_ids = ["subnet-aaaaa", "subnet-bbbbb"]  # Dev VPC subnets (different AZs)
vpc_endpoint_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef"  # From Step 1
redis_port = 6379
number_of_endpoints = 3
environment = "dev"
EOF

# Initialize and plan
terraform init
terraform plan

# Apply
terraform apply
```

### Step 3: Accept VPC Endpoint Connections

After Step 2, the VPC endpoints will be in "pendingAcceptance" state. Accept them in the **Prod Account**:

**Option A: AWS Console**
1. Go to **Prod Account** → VPC → Endpoint Services
2. Select your endpoint service (`joda-redis-onprem-service`)
3. Go to "Endpoint Connections" tab
4. Select pending connections → Actions → Accept endpoint connection request

**Option B: AWS CLI**
```bash
# In Prod Account
aws ec2 accept-vpc-endpoint-connections \
  --service-id <vpc-endpoint-service-id> \
  --vpc-endpoint-ids <endpoint-id-1> <endpoint-id-2> <endpoint-id-3>
```

**Option C: Terraform** (if using accept-endpoint.tf)
```bash
cd terraform/prod-account
terraform apply  # This will accept pending connections
```

### Step 4: Verify Connectivity

From an EC2 instance in Dev VPC:

```bash
# Get endpoint DNS names
cd terraform/joda-toda-account
terraform output vpc_endpoint_dns_names

# Test Redis connection
redis-cli -h <endpoint-dns-name-1> -p 6379 ping
redis-cli -h <endpoint-dns-name-2> -p 6379 ping
redis-cli -h <endpoint-dns-name-3> -p 6379 ping
```

### Step 5: Configure Applications

Update your application configuration to use the VPC endpoint DNS names:

```python
# Example Python Redis client configuration
import redis

# Get endpoint DNS names from Terraform output
redis_endpoints = [
    "vpce-xxxxx-xxxxx.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com",
    "vpce-yyyyy-yyyyy.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com",
    "vpce-zzzzz-zzzzz.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com"
]

# Connect to all endpoints for high availability
# Use Redis Sentinel or Cluster mode, or implement client-side load balancing
```

## Network Verification

### Verify Route Tables
**CRITICAL**: Ensure Prod VPC route tables allow traffic to on-premises network (10.0.0.0/16) via Transit Gateway.

```bash
# In Prod Account - Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<prod-vpc-id>"
```

Route should exist: `10.0.0.0/16 → Transit Gateway`

### Verify NLB Health Checks
```bash
# In Prod Account
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

### Verify VPC Endpoint Status
```bash
# In Joda-Toda-AWS Account
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids <endpoint-id-1> <endpoint-id-2> <endpoint-id-3>
```

### Verify Route Tables (Dev VPC)
Ensure Dev VPC route tables allow traffic to VPC endpoints (should be automatic with PrivateLink).

## Troubleshooting

### Endpoints stuck in "pendingAcceptance"
- Verify consumer account ID is in allowed principals
- Check IAM permissions
- Accept connections manually in **Prod Account** (not Connectivity Account)

### Cannot reach Redis servers
- **CRITICAL**: Verify Prod VPC route tables allow traffic to on-premises (10.0.0.0/16) via TGW
- Verify TGW routing to Connectivity Account → Direct Connect
- Check NLB target group health checks
- Verify security groups allow traffic on Redis port
- Check VPC route tables in Prod Account
- Verify endpoints are accepted in Prod Account
- Verify Direct Connect is operational (in Connectivity Account - no changes needed)

### High latency
- Ensure endpoints are in the same region
- Check Direct Connect bandwidth utilization
- Verify NLB health checks are passing

## Cost Monitoring

Monitor costs in both accounts:

**Prod Account:**
- NLB: ~$16/month
- VPC Endpoint Service: Free
- Data transfer: ~$0.01/GB (same region)
- TGW Data Transfer: ~$0.02/GB (cross-account routing)

**Joda-Toda-AWS Account:**
- VPC Endpoints (3): ~$22/month (~$7.20/month each)
- Data transfer: ~$0.01/GB (same region)

**Connectivity Account:**
- No additional costs (no changes made)

Set up CloudWatch billing alarms to monitor costs.

## Security Checklist

- [ ] Endpoint acceptance required (manual approval)
- [ ] Security groups restrict to Redis port only
- [ ] VPC Flow Logs enabled
- [ ] IAM policies follow least privilege
- [ ] Only Dev VPC has access (Stage/Prod isolated)
- [ ] Network ACLs configured appropriately

## Cleanup

To remove the infrastructure:

```bash
# Joda-Toda-AWS Account
cd terraform/joda-toda-account
terraform destroy

# Prod Account
cd terraform/prod-account
terraform destroy
```

**Note**: Connectivity Account remains untouched - no cleanup needed there.

## Support

For issues or questions:
1. Check CloudWatch logs in Prod Account
2. Review VPC Flow Logs in Prod Account
3. Verify security groups and route tables in Prod Account
4. Verify route tables allow traffic to on-premises (10.0.0.0/16) via TGW
5. Check Transit Gateway routing
6. Verify Direct Connect status (in Connectivity Account - no changes needed)

## Key Points

✅ **Connectivity Account**: No changes required - remains completely untouched  
✅ **Prod Account**: All PrivateLink infrastructure created here  
✅ **Routing**: NLB reaches Redis via Prod VPC → TGW → Connectivity Account → Direct Connect  
✅ **Route Tables**: Must allow traffic to 10.0.0.0/16 via TGW in Prod VPC

