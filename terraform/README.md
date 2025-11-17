# Terraform Structure for Joda-Toda PrivateLink Solution

## 📁 Directory Structure

```
terraform/
├── README.md                          # This file
├── prod-account/                      # Provider Account (Joda Prod Account)
│   ├── single-nlb/                   # ✅ RECOMMENDED: Single NLB approach
│   │   └── main.tf                   # Creates 1 NLB with 3 target groups
│   └── three-nlbs/                   # Alternative: Three NLBs approach
│       └── main.tf                   # Creates 3 NLBs (what engineer did)
├── joda-toda-account/                 # Consumer Account (Joda-Toda-AWS)
│   └── main.tf                       # Creates VPC endpoints in Dev VPC
├── route53-weighted-routing/          # Optional: Route 53 configuration
│   └── main.tf                       # Route 53 weighted routing (not recommended)
└── JODA_TODA_DEPLOYMENT.md           # Deployment guide
```

## 🎯 Which Approach to Use?

### ✅ **Single NLB Approach** (Recommended)
- **Location**: `prod-account/single-nlb/`
- **Cost**: ~$16/month
- **Best for**: Most use cases
- **How it works**: One NLB with 3 target groups, application connects to all 3 endpoints

### ⚠️ **Three NLBs Approach** (What Engineer Created)
- **Location**: `prod-account/three-nlbs/`
- **Cost**: ~$48/month
- **Use case**: If you need individual server access or Route 53 weighted routing
- **How it works**: Three separate NLBs, each with its own endpoint service

## 🚀 Quick Start

### Option 1: Single NLB (Recommended)

**Step 1: Deploy in Prod Account**
```bash
cd terraform/prod-account/single-nlb

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region = "us-east-1"
prod_vpc_id = "vpc-xxxxxxxxx"
prod_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
redis_server_ips = ["10.0.4.10", "10.0.4.11", "10.0.4.12"]
redis_port = 6379
consumer_account_id = "123456789012"
endpoint_service_name = "joda-redis-onprem-service"
EOF

terraform init
terraform plan
terraform apply
```

**Step 2: Deploy in Joda-Toda-AWS Account**
```bash
cd terraform/joda-toda-account

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region = "us-east-1"
dev_vpc_id = "vpc-zzzzzzzzz"
dev_subnet_ids = ["subnet-aaaaa", "subnet-bbbbb"]
vpc_endpoint_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx"  # From Step 1
redis_port = 6379
number_of_endpoints = 3
environment = "dev"
EOF

terraform init
terraform plan
terraform apply
```

**Step 3: Accept Connections**
- Go to Prod Account → VPC → Endpoint Services → [Service Name] → Endpoint Connections → Accept

### Option 2: Three NLBs (Current Implementation)

**Step 1: Deploy in Prod Account**
```bash
cd terraform/prod-account/three-nlbs

# Create terraform.tfvars (same as above)
terraform init
terraform plan
terraform apply
```

**Step 2: Deploy in Joda-Toda-AWS Account**
```bash
cd terraform/joda-toda-account

# Note: You'll need to create 3 separate endpoint resources
# Or modify main.tf to accept multiple service names
```

## 📋 Prerequisites

### Prod Account
- ✅ AWS CLI configured with Prod Account credentials
- ✅ Prod VPC ID (10.2.0.0/16)
- ✅ Subnets in Prod VPC that can reach on-premises via TGW
- ✅ Route tables configured to allow traffic to 10.0.0.0/16 via TGW
- ✅ On-premises Redis server IPs
- ✅ Joda-Toda-AWS account ID

### Joda-Toda-AWS Account
- ✅ AWS CLI configured with Joda-Toda-AWS account credentials
- ✅ Dev VPC ID (10.3.0.0/16)
- ✅ At least 2 subnets in Dev VPC (different AZs)

## 🔑 Key Differences

| Feature | Single NLB | Three NLBs |
|---------|-----------|------------|
| **Cost** | ~$16/month | ~$48/month |
| **NLBs** | 1 | 3 |
| **Endpoint Services** | 1 | 3 |
| **VPC Endpoints** | 3 | 3 |
| **Complexity** | Low | High |
| **Route 53** | Not needed | Possible (not recommended) |
| **Application Config** | Connect to all 3 endpoints | Connect to all 3 endpoints |

## ⚠️ Important Notes

1. **Connectivity Account**: No changes required - remains untouched
2. **Route Tables**: Prod VPC must allow traffic to 10.0.0.0/16 via TGW
3. **Route 53**: Not recommended for Redis (see `ROUTE53_RECOMMENDATIONS.md`)
4. **Application**: Should connect to all 3 endpoints directly, use Redis Sentinel/Cluster

## 📚 Additional Documentation

- **Deployment Guide**: `JODA_TODA_DEPLOYMENT.md`
- **Route 53 Analysis**: `../ROUTE53_APPROACH.md`
- **Route 53 Recommendations**: `../ROUTE53_RECOMMENDATIONS.md`
- **Solution Overview**: `../JODA_TODA_SOLUTION.md`

## 🆘 Troubleshooting

### NLB cannot reach Redis servers
- Verify route tables in Prod VPC allow traffic to 10.0.0.0/16 via TGW
- Check TGW routing to Connectivity Account
- Verify Direct Connect is operational

### Endpoints stuck in pendingAcceptance
- Accept connections in Prod Account (not Connectivity Account)
- Verify consumer account ID is in allowed principals

### High latency
- Ensure endpoints are in same region
- Check TGW bandwidth utilization
- Verify NLB health checks are passing

## 💰 Cost Comparison

| Component | Single NLB | Three NLBs |
|-----------|-----------|------------|
| NLB | $16/month | $48/month |
| VPC Endpoint Service | Free | Free |
| VPC Endpoints (3) | $22/month | $22/month |
| **Total** | **~$38/month** | **~$70/month** |

## 🎯 Recommendation

**Use Single NLB approach** (`prod-account/single-nlb/`) because:
- ✅ Lower cost (~$32/month savings)
- ✅ Simpler to manage
- ✅ Better for Redis workloads
- ✅ Same functionality

Use Three NLBs only if you specifically need individual server access or Route 53 weighted routing (which is not recommended for Redis anyway).
