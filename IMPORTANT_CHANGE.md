# Important Architecture Change

## Summary

**All PrivateLink infrastructure is now deployed from the Prod Account, NOT the Connectivity Account.**

## Why This Change?

The manager does not want anyone to touch the Connectivity Account. Therefore, all PrivateLink components (NLB and VPC Endpoint Service) are created in the Prod Account instead.

## Architecture Flow

### Previous (Not Used)
```
On-Prem Redis → Direct Connect → Connectivity Account → NLB → Endpoint Service → PrivateLink → Joda-Toda-AWS
```

### Current (Implemented)
```
On-Prem Redis → Direct Connect → Connectivity Account → TGW → Prod Account → NLB → Endpoint Service → PrivateLink → Joda-Toda-AWS
```

## Key Points

✅ **Connectivity Account**: Completely untouched - no changes required  
✅ **Prod Account**: All PrivateLink infrastructure created here  
✅ **Routing**: NLB reaches Redis via Prod VPC → TGW → Connectivity Account → Direct Connect  
✅ **Route Tables**: Must be configured in Prod VPC to allow traffic to on-premises (10.0.0.0/16) via TGW

## Components Location

| Component | Account | VPC | Notes |
|-----------|---------|-----|-------|
| **NLB** | Prod Account | VPC-Prod (10.2.0.0/16) | Reaches Redis via TGW |
| **VPC Endpoint Service** | Prod Account | VPC-Prod (10.2.0.0/16) | Shared with Joda-Toda-AWS |
| **VPC Endpoints** | Joda-Toda-AWS Account | VPC-Dev (10.3.0.0/16) | Consumer endpoints |
| **Direct Connect Gateway** | Connectivity Account | VPC-Connectivity | **No changes** |
| **Transit Gateway** | Connectivity Account | VPC-Connectivity | **No changes** |

## Deployment

1. **Deploy from Prod Account**: Use `terraform/prod-account/`
2. **Accept connections in Prod Account**: Not Connectivity Account
3. **Verify route tables**: Ensure Prod VPC can reach on-premises via TGW

## Files Updated

- ✅ `JODA_TODA_SOLUTION.md` - Updated architecture
- ✅ `terraform/prod-account/main.tf` - New Terraform code for Prod Account
- ✅ `terraform/JODA_TODA_DEPLOYMENT.md` - Updated deployment guide
- ✅ `joda-toda-privatelink.drawio` - Updated diagram showing NLB in Prod Account

## Critical Requirements

⚠️ **Route Tables**: Prod VPC route tables MUST allow traffic to on-premises network (10.0.0.0/16) via Transit Gateway. Without this, the NLB cannot reach Redis servers.

To verify:
```bash
# In Prod Account
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<prod-vpc-id>"
```

Look for route: `10.0.0.0/16 → Transit Gateway`

