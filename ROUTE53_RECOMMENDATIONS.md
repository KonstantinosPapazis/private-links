# Route 53 Weighted Routing - Recommendations for Redis

## Current Situation

The engineer created 3 separate PrivateLinks (3 NLBs, 3 Endpoint Services) and is trying to use Route 53 weighted routing as a "pseudo load balancer."

## The Problem

**Route 53 weighted routing is NOT ideal for Redis** because:

1. **DNS Caching**: Redis clients cache DNS lookups. Once resolved, they keep using the same IP.
2. **Persistent Connections**: Redis maintains long-lived connections. DNS changes don't affect existing connections.
3. **Load Distribution**: Weighted routing only affects NEW connections, leading to uneven distribution over time.
4. **Cost**: 3 NLBs cost ~$48/month vs ~$16/month for single NLB.

## What Actually Happens

```
Time 0:  Application resolves DNS → Gets endpoint-1 (33% weight)
Time 1:  Application resolves DNS → Gets endpoint-2 (33% weight)  
Time 2:  Application resolves DNS → Gets endpoint-3 (34% weight)

BUT: Each Redis client maintains its connection to the endpoint it first resolved.
     Over time, connections accumulate unevenly.
```

## Solutions

### Option 1: Keep 3 NLBs but Use Application-Level Load Balancing (Recommended)

**Instead of Route 53**, configure your application to:

1. **Connect to all 3 endpoints directly**
2. **Use Redis Sentinel or Cluster mode**
3. **Implement client-side load balancing**

**Example (Python)**:
```python
import redis
from redis.sentinel import Sentinel

# Configure Sentinel with all 3 endpoints
sentinel = Sentinel([
    ('vpce-xxx.vpce-svc-xxx.vpce.us-east-1.vpce.amazonaws.com', 6379),
    ('vpce-yyy.vpce-svc-yyy.vpce.us-east-1.vpce.amazonaws.com', 6379),
    ('vpce-zzz.vpce-svc-zzz.vpce.us-east-1.vpce.amazonaws.com', 6379)
], socket_timeout=0.1)

# Get master connection
master = sentinel.master_for('mymaster', socket_timeout=0.1)
```

**Benefits**:
- ✅ Works with persistent connections
- ✅ True load balancing
- ✅ Supports Redis HA features
- ✅ No DNS caching issues

### Option 2: Consolidate to Single NLB (Best Cost/Complexity)

**Change architecture to**:
- 1 NLB with 3 target groups
- Application connects to all 3 endpoints
- Use Redis Sentinel/Cluster

**Benefits**:
- ✅ Lower cost (~$16/month vs ~$48/month)
- ✅ Simpler to manage
- ✅ Better for Redis workloads
- ✅ Same functionality

### Option 3: If You Must Use Route 53

**If Route 53 weighted routing is required**, optimize it:

1. **Enable Health Checks**: Configure Route 53 health checks
2. **Low TTL**: Set DNS TTL to 60 seconds or less
3. **Application Retry**: Implement retry logic for failed connections
4. **Monitor**: Use CloudWatch to track distribution
5. **Accept Limitations**: Understand it's not true load balancing

**Configuration**:
```hcl
# See terraform/route53-weighted-routing/main.tf for full example
resource "aws_route53_record" "redis_weighted" {
  count = 3
  
  weighted_routing_policy {
    weight = count.index == 2 ? 34 : 33
  }
  
  health_check_id = aws_route53_health_check.redis_endpoints[count.index].id
  ttl = 60  # Low TTL
}
```

## Comparison Table

| Approach | Cost/Month | Complexity | Effectiveness | Redis Support |
|----------|------------|------------|---------------|---------------|
| **3 NLBs + Route 53** | ~$48 | High | Low | Poor |
| **3 NLBs + App-Level** | ~$48 | Medium | High | Excellent |
| **Single NLB + App-Level** | ~$16 | Low | High | Excellent |

## Recommendation

**Best Approach**: Consolidate to **single NLB** and use **application-level Redis Sentinel/Cluster** configuration.

**Why**:
1. Lower cost (~$32/month savings)
2. Better suited for Redis workloads
3. Simpler architecture
4. No DNS caching issues
5. Supports Redis HA features

**If you must keep 3 NLBs**: Use application-level load balancing instead of Route 53.

## Migration Path

### From Route 53 to Application-Level:

1. **Keep existing 3 NLBs** (no infrastructure changes)
2. **Update application configuration**:
   - Remove Route 53 DNS name
   - Connect directly to all 3 VPC endpoint DNS names
   - Configure Redis Sentinel or Cluster mode
3. **Test**: Verify load distribution and failover
4. **Monitor**: Use CloudWatch to track connections

### From 3 NLBs to Single NLB:

1. **Create single NLB** with 3 target groups (in Prod Account)
2. **Create single VPC Endpoint Service** from the NLB
3. **Update Joda-Toda-AWS endpoints** to use new service
4. **Test**: Verify connectivity
5. **Decommission**: Remove old 3 NLBs and endpoint services
6. **Update application**: Connect to new endpoints

## Code Examples

See:
- `terraform/route53-weighted-routing/main.tf` - Route 53 configuration (if needed)
- `terraform/prod-account/main.tf` - Single NLB approach (recommended)
- `terraform/joda-toda-account/main.tf` - Consumer endpoints

## Questions to Ask the Engineer

1. **Why Route 53?** What problem are you trying to solve?
2. **Redis Mode**: Are you using Redis Sentinel, Cluster, or standalone?
3. **Connection Pattern**: Are connections long-lived or short-lived?
4. **Load Distribution**: Have you measured actual traffic distribution?
5. **Cost Consideration**: Is the extra cost (~$32/month) justified?

## Conclusion

Route 53 weighted routing **can work** but is **not optimal** for Redis. Consider:
- **Short-term**: Keep 3 NLBs, switch to application-level load balancing
- **Long-term**: Consolidate to single NLB with application-level HA

The single NLB approach provides better cost, simplicity, and Redis compatibility.

