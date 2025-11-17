# Joda-Toda-AWS Account - VPC Endpoints

This directory contains Terraform code to create VPC endpoints in the Joda-Toda-AWS Dev VPC.

## Usage

### For Single NLB Approach

```hcl
# terraform.tfvars
vpc_endpoint_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx"
number_of_endpoints = 3
```

### For Three NLBs Approach

```hcl
# terraform.tfvars
vpc_endpoint_service_names = [
  "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx",
  "com.amazonaws.vpce.us-east-1.vpce-svc-yyyyy",
  "com.amazonaws.vpce.us-east-1.vpce-svc-zzzzz"
]
```

## Variables

- `vpc_endpoint_service_name`: Single service name (for single NLB approach)
- `vpc_endpoint_service_names`: List of service names (for three NLBs approach)
- `dev_vpc_id`: Dev VPC ID
- `dev_subnet_ids`: Subnet IDs for endpoints (at least 2 in different AZs)
- `number_of_endpoints`: Number of endpoints to create (default: 3)

## Outputs

- `vpc_endpoint_dns_names`: DNS names to use for Redis connections
- `vpc_endpoint_ids`: Endpoint IDs (for acceptance in Prod Account)

