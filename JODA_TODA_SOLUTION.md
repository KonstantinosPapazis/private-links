# Joda-Toda PrivateLink Solution

## Architecture Overview

After Joda company acquired Toda company, a new AWS account **Joda-Toda-AWS** was created with 3 VPCs:
- **VPC-Dev**: Routable with Joda network (via Transit Gateway)
- **VPC-Stage**: Routable with Toda network
- **VPC-Prod**: Routable with Toda network

**Requirement**: Provide Joda-Toda-AWS account access to on-premises Redis servers using **AWS PrivateLink**.

## Solution Architecture

```
On-Prem Redis → Direct Connect → Connectivity Account → TGW → Prod Account → NLB → VPC Endpoint Service → PrivateLink → Joda-Toda-AWS (Dev VPC) → VPC Endpoints
```

**Important**: All PrivateLink infrastructure is created in **Prod Account** (not Connectivity Account) to avoid touching the connectivity account.

## Implementation Details

### Step 1: Create PrivateLink Infrastructure in Prod Account

**Location**: AWS Prod Account (has access to on-premises via Transit Gateway)

**Components to Create:**

1. **Network Load Balancer (NLB)**
   - Type: Internal Network Load Balancer
   - Subnets: Subnets in Prod VPC that can reach on-premises via Transit Gateway
   - Target Groups: 3 target groups (one per Redis server)
     - Target Type: IP addresses
     - Targets: On-premises Redis server IPs (10.0.4.x)
     - Health Checks: TCP on port 6379
   - **Routing**: NLB reaches Redis via Prod VPC → TGW → Connectivity Account → Direct Connect → On-Prem

2. **VPC Endpoint Service**
   - Created from the NLB
   - Acceptance Required: Yes (for security)
   - Allowed Principals: Joda-Toda-AWS account ID
   - Service Name: Will be shared with consumer account

### Step 2: Create VPC Endpoints in Joda-Toda-AWS Account

**Location**: Joda-Toda-AWS Account → **Dev VPC only**

**Components to Create:**

1. **VPC Endpoints** (3 endpoints)
   - Type: Interface endpoints
   - Service Name: From Connectivity Account endpoint service
   - Subnets: At least 2 subnets in different AZs for HA
   - Security Groups: Restrict to Redis port (6379)
   - Private DNS: Enabled (for easier connection)

**Note**: Only Dev VPC needs PrivateLink because:
- Dev VPC is routable with Joda network (can use PrivateLink)
- Stage and Prod VPCs are routable with Toda network (separate network, no need for Joda Redis access)

## Network Flow

### Joda-Toda Dev VPC → On-Premises Redis

```
Dev Application → Dev VPC → VPC Endpoint → PrivateLink (AWS Backbone) → 
Prod Account Endpoint Service → NLB → TGW → Connectivity Account → Direct Connect → On-Premises Redis
```

**Key Points:**
- Traffic stays within AWS backbone (never touches public internet)
- Secure, private connectivity
- No need for additional Direct Connect or VPN for Joda-Toda account
- Dev VPC can still use TGW for other Joda network resources

## VPC Configuration Summary

| VPC | CIDR | Network Access | PrivateLink Access | Notes |
|-----|------|----------------|-------------------|-------|
| **Dev** | 10.3.0.0/16 | ✅ Joda Network (via TGW) | ✅ Yes | Can access Redis via PrivateLink |
| **Stage** | 10.4.0.0/16 | ⚠️ Toda Network | ❌ No | Separate network, no Redis access needed |
| **Prod** | 10.5.0.0/16 | ⚠️ Toda Network | ❌ No | Separate network, no Redis access needed |

## Why PrivateLink for Dev VPC?

Even though Dev VPC is routable with Joda network via Transit Gateway, PrivateLink provides:

1. **Security Isolation**: Direct, secure connection to Redis without routing through entire network
2. **Performance**: Optimized path for Redis traffic
3. **Compliance**: Traffic stays within AWS backbone
4. **Simplicity**: No complex routing rules needed
5. **Scalability**: Easy to add more consumer accounts in the future

## Implementation Steps

### Phase 1: Prod Account Setup

1. **Create NLB in Prod VPC**
   ```bash
   # Use Terraform in terraform/prod-account/
   # Configure:
   # - VPC: Prod VPC (10.2.0.0/16)
   # - Subnets: Subnets in Prod VPC
   # - Target Groups: 3 groups targeting Redis IPs (10.0.4.x)
   # - Routing: NLB reaches Redis via TGW → Connectivity Account → Direct Connect
   ```

2. **Create VPC Endpoint Service**
   ```bash
   # Share service with Joda-Toda-AWS account ID
   # Enable acceptance required
   ```

3. **Accept Endpoint Connections**
   - After consumer creates endpoints, accept them in **Prod Account**

### Phase 2: Joda-Toda-AWS Account Setup

1. **Create VPC Endpoints in Dev VPC**
   ```bash
   # Use Terraform in terraform/consumer-account/
   # Configure:
   # - VPC: Dev VPC (10.3.0.0/16)
   # - Service Name: From Connectivity Account
   # - Number of Endpoints: 3
   ```

2. **Configure Application**
   - Update Redis connection strings to use VPC endpoint DNS names
   - Connect to all 3 endpoints for high availability

## Security Considerations

1. **Endpoint Acceptance**: Manual approval required in **Prod Account**
2. **Security Groups**: Restrict access to Redis port (6379) only
3. **VPC Flow Logs**: Enable for audit trail
4. **IAM Policies**: Least privilege access
5. **Network Isolation**: Only Dev VPC has access, Stage/Prod VPCs are isolated
6. **Connectivity Account**: No changes required - remains untouched

## Cost Estimation

**Prod Account:**
- NLB: ~$16/month
- VPC Endpoint Service: Free
- Data Transfer: ~$0.01/GB (same region)
- TGW Data Transfer: ~$0.02/GB (cross-account)

**Joda-Toda-AWS Account:**
- VPC Endpoints (3): ~$22/month (~$7.20/month each)
- Data Transfer: ~$0.01/GB (same region)

**Total Base Cost**: ~$38/month + data transfer (slightly higher due to TGW routing)

## High Availability

- **NLB**: Health checks ensure only healthy Redis servers receive traffic
- **VPC Endpoints**: Created in multiple AZs for redundancy
- **Application**: Connects to all 3 endpoints for Redis cluster/sentinel support

## Monitoring

- **CloudWatch Metrics**: Monitor NLB and endpoint health
- **VPC Flow Logs**: Track traffic patterns
- **Health Checks**: Automatic failover for unhealthy Redis servers

## Next Steps

1. Review architecture diagram (`joda-toda-privatelink.drawio`)
2. Deploy Terraform code in **Prod Account** (not Connectivity Account)
3. Deploy Terraform code in Joda-Toda-AWS Dev VPC
4. Accept endpoint connections in Prod Account
5. Test connectivity and configure applications
6. Monitor costs and performance

## Files Reference

- **Architecture Diagram**: `joda-toda-privatelink.drawio`
- **Terraform Provider**: `terraform/prod-account/` (creates NLB and endpoint service)
- **Terraform Consumer**: `terraform/joda-toda-account/` (creates VPC endpoints)
- **Current Architecture**: `CURRENT_ARCHITECTURE.md`

## Key Benefits of This Approach

✅ **Connectivity Account Untouched**: No changes required to Connectivity Account  
✅ **Prod Account Control**: All PrivateLink infrastructure managed in Prod Account  
✅ **Existing Routing**: Leverages existing TGW routing to reach on-premises  
✅ **Security**: Same security benefits with better operational control

