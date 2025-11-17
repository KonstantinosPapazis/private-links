# Terraform Structure - Quick Reference

## 📁 Current Structure

```
terraform/
├── README.md                          # Main documentation
├── STRUCTURE.md                       # This file - quick reference
│
├── prod-account/                      # Provider Account (Joda Prod Account)
│   ├── single-nlb/                   # ✅ RECOMMENDED
│   │   ├── main.tf                  # Creates 1 NLB with 3 target groups
│   │   └── terraform.tfvars.example # Example configuration
│   └── three-nlbs/                   # Alternative (what engineer did)
│       ├── main.tf                  # Creates 3 NLBs
│       └── terraform.tfvars.example # Example configuration
│
├── joda-toda-account/                 # Consumer Account (Joda-Toda-AWS)
│   ├── main.tf                      # Creates VPC endpoints (supports both approaches)
│   ├── README.md                    # Usage guide
│   └── terraform.tfvars.example     # Example configuration
│
├── route53-weighted-routing/          # Optional (not recommended)
│   └── main.tf                      # Route 53 configuration
│
└── JODA_TODA_DEPLOYMENT.md           # Full deployment guide
```

## 🎯 Which Files to Use?

### Scenario 1: Starting Fresh (Recommended)
1. **Prod Account**: `prod-account/single-nlb/main.tf`
2. **Joda-Toda-AWS**: `joda-toda-account/main.tf` (with single service name)

### Scenario 2: Engineer Already Created 3 NLBs
1. **Prod Account**: Already deployed (3 NLBs exist)
2. **Joda-Toda-AWS**: `joda-toda-account/main.tf` (with service names list)

## 📝 Quick Start Commands

### Single NLB Approach

```bash
# 1. Prod Account
cd terraform/prod-account/single-nlb
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply

# 2. Joda-Toda-AWS Account
cd ../../joda-toda-account
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - use vpc_endpoint_service_name from step 1
terraform init && terraform apply

# 3. Accept connections in Prod Account (AWS Console)
```

### Three NLBs Approach

```bash
# 1. Prod Account
cd terraform/prod-account/three-nlbs
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply

# 2. Joda-Toda-AWS Account
cd ../../joda-toda-account
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - use vpc_endpoint_service_names list from step 1
terraform init && terraform apply

# 3. Accept connections in Prod Account (AWS Console)
```

## 🔑 Key Variables

### Prod Account (single-nlb)
- `prod_vpc_id`: Prod VPC ID
- `prod_subnet_ids`: Subnets for NLB
- `redis_server_ips`: List of 3 Redis IPs
- `consumer_account_id`: Joda-Toda-AWS account ID

### Prod Account (three-nlbs)
- Same as above, but creates 3 NLBs instead of 1

### Joda-Toda-AWS Account
- `dev_vpc_id`: Dev VPC ID
- `dev_subnet_ids`: Subnets for endpoints
- `vpc_endpoint_service_name`: Single service name (for single NLB)
- `vpc_endpoint_service_names`: List of 3 service names (for three NLBs)

## ✅ What Was Removed?

- ❌ `connectivity-account/` - Not used (Connectivity Account untouched)
- ❌ `provider-account/` - Generic, replaced with specific `prod-account/`
- ❌ `consumer-account/` - Generic, replaced with specific `joda-toda-account/`

## 📚 Documentation

- **Main README**: `README.md` - Complete guide
- **Deployment Guide**: `JODA_TODA_DEPLOYMENT.md` - Step-by-step instructions
- **This File**: `STRUCTURE.md` - Quick reference

