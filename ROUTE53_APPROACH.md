# Route 53 Weighted Routing Approach Analysis

## Current Implementation

The Joda engineer created:
- **3 separate NLBs** (one per Redis server)
- **3 separate VPC Endpoint Services** (one per NLB)
- **3 VPC Endpoints** in Joda-Toda-AWS Dev VPC
- **Route 53 weighted routing** to distribute traffic across the 3 endpoints

## Architecture

```
On-Prem Redis (3 servers)
    ↓
Direct Connect → Connectivity Account → TGW → Prod Account
    ↓
┌─────────────────────────────────────────────────────────┐
│  Prod Account                                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │  NLB-1   │  │  NLB-2   │  │  NLB-3   │            │
│  │(Redis-1) │  │(Redis-2) │  │(Redis-3) │            │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
│       │             │             │                    │
│  ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐            │
│  │Endpoint  │  │Endpoint  │  │Endpoint  │            │
│  │Service 1 │  │Service 2 │  │Service 3 │            │
│  └──────────┘  └──────────┘  └──────────┘            │
└─────────────────────────────────────────────────────────┘
    ↓              ↓              ↓
    └──────────────┴──────────────┘
                    ↓
        Route 53 Weighted Routing
                    ↓
┌─────────────────────────────────────────────────────────┐
│  Joda-Toda-AWS Dev VPC                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │Endpoint 1│  │Endpoint 2│  │Endpoint 3│            │
│  └──────────┘  └──────────┘  └──────────┘            │
│       ↓             ↓             ↓                      │
│       └─────────────┴─────────────┘                      │
│                    ↓                                      │
│            Applications                                   │
└─────────────────────────────────────────────────────────┘
```

## Route 53 Weighted Routing Configuration

### DNS Record Setup

Create a Route 53 alias or CNAME record with weighted routing:

```
redis.joda-toda.internal.  A  Weighted
  - redis-endpoint-1.vpce-svc-xxx.vpce.us-east-1.vpce.amazonaws.com  Weight: 33
  - redis-endpoint-2.vpce-svc-yyy.vpce.us-east-1.vpce.amazonaws.com  Weight: 33
  - redis-endpoint-3.vpce-svc-zzz.vpce.us-east-1.vpce.amazonaws.com  Weight: 34
```

### Terraform Example

```hcl
# Route 53 Private Hosted Zone
resource "aws_route53_zone" "internal" {
  name = "joda-toda.internal"
  vpc {
    vpc_id = var.dev_vpc_id
  }
}

# Weighted Route 53 Records
resource "aws_route53_record" "redis_weighted" {
  count = 3
  
  zone_id = aws_route53_zone.internal.zone_id
  name    = "redis.joda-toda.internal"
  type    = "A"
  
  set_identifier = "redis-endpoint-${count.index + 1}"
  weighted_routing_policy {
    weight = 33 + (count.index == 2 ? 1 : 0)  # 33, 33, 34
  }
  
  alias {
    name                   = aws_vpc_endpoint.redis_endpoints[count.index].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.redis_endpoints[count.index].dns_entry[0].hosted_zone_id
    evaluate_target_health = true  # Enable health checks
  }
}
```

## Pros and Cons

### ✅ Pros

1. **Individual Server Access**: Can target specific Redis servers directly
2. **DNS-Based Load Balancing**: Simple to configure
3. **Health Checks**: Route 53 can check endpoint health
4. **Flexibility**: Can adjust weights dynamically
5. **No Single Point of Failure**: Each NLB is independent

### ⚠️ Cons

1. **Cost**: 3 NLBs = ~$48/month (vs ~$16/month for single NLB)
2. **Complexity**: More components to manage
3. **DNS Caching**: Clients cache DNS, reducing effectiveness of weighted routing
4. **Not True Load Balancing**: DNS-based, not connection-based
5. **Redis-Specific Issues**: 
   - Redis connections are persistent
   - DNS changes don't affect existing connections
   - Not ideal for Redis cluster/sentinel modes
6. **Route 53 Limitations**: 
   - Weighted routing is probabilistic, not deterministic
   - Health checks are DNS-level, not application-level
   - TTL caching can cause uneven distribution

## Critical Issues with This Approach

### 1. DNS Caching Problem

**Issue**: Redis clients typically cache DNS lookups. Once a client resolves the DNS name, it will continue using that IP address for the duration of the connection.

**Impact**: 
- Weighted routing only affects NEW connections
- Existing connections stay on the same endpoint
- Load distribution becomes uneven over time

### 2. Redis Connection Persistence

**Issue**: Redis clients maintain persistent connections. DNS changes don't affect active connections.

**Impact**:
- Route 53 weighted routing only works for new connections
- Not effective for long-lived Redis connections
- Can lead to uneven load distribution

### 3. Health Check Limitations

**Issue**: Route 53 health checks are DNS-level (endpoint reachability), not Redis-level (Redis server health).

**Impact**:
- Route 53 might route to an endpoint even if Redis server is down
- NLB health checks are separate from Route 53 health checks
- Need to coordinate health checks between Route 53 and NLB

## Better Alternatives

### Option 1: Single NLB with Multiple Target Groups (Recommended)

**Architecture**:
- One NLB with 3 target groups
- Application connects to all 3 endpoints directly
- Use Redis Sentinel or Cluster mode for HA

**Benefits**:
- Lower cost (~$16/month vs ~$48/month)
- Better for Redis (supports Sentinel/Cluster)
- Application-level control
- No DNS caching issues

### Option 2: Route 53 with Health Checks + Failover

**Architecture**:
- Use Route 53 weighted routing WITH health checks
- Configure health checks to monitor Redis endpoints
- Use failover routing for high availability

**Configuration**:
```hcl
resource "aws_route53_health_check" "redis_endpoints" {
  count = 3
  
  fqdn              = aws_vpc_endpoint.redis_endpoints[count.index].dns_entry[0].dns_name
  port              = 6379
  type              = "TCP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name = "redis-endpoint-${count.index + 1}-health"
  }
}

resource "aws_route53_record" "redis_weighted_with_health" {
  count = 3
  
  zone_id = aws_route53_zone.internal.zone_id
  name    = "redis.joda-toda.internal"
  type    = "A"
  
  set_identifier = "redis-endpoint-${count.index + 1}"
  weighted_routing_policy {
    weight = 33 + (count.index == 2 ? 1 : 0)
  }
  
  health_check_id = aws_route53_health_check.redis_endpoints[count.index].id
  
  alias {
    name                   = aws_vpc_endpoint.redis_endpoints[count.index].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.redis_endpoints[count.index].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}
```

### Option 3: Application-Level Load Balancing

**Architecture**:
- Application connects to all 3 endpoints
- Client-side load balancing (round-robin, least connections, etc.)
- Use Redis client libraries that support multiple endpoints

**Example (Python)**:
```python
import redis
from redis.sentinel import Sentinel

# Option A: Redis Sentinel
sentinel = Sentinel([
    ('redis-endpoint-1.vpce-svc-xxx.vpce.us-east-1.vpce.amazonaws.com', 6379),
    ('redis-endpoint-2.vpce-svc-yyy.vpce.us-east-1.vpce.amazonaws.com', 6379),
    ('redis-endpoint-3.vpce-svc-zzz.vpce.us-east-1.vpce.amazonaws.com', 6379)
], socket_timeout=0.1)

master = sentinel.master_for('mymaster', socket_timeout=0.1)

# Option B: Client-side round-robin
import random

redis_endpoints = [
    'redis-endpoint-1.vpce-svc-xxx.vpce.us-east-1.vpce.amazonaws.com',
    'redis-endpoint-2.vpce-svc-yyy.vpce.us-east-1.vpce.amazonaws.com',
    'redis-endpoint-3.vpce-svc-zzz.vpce.us-east-1.vpce.amazonaws.com'
]

def get_redis_client():
    endpoint = random.choice(redis_endpoints)
    return redis.Redis(host=endpoint, port=6379)
```

## Recommendations

### If You Must Use Route 53 Weighted Routing:

1. **Enable Health Checks**: Configure Route 53 health checks for each endpoint
2. **Use Low TTL**: Set DNS TTL to 60 seconds or less
3. **Monitor Distribution**: Use CloudWatch to monitor traffic distribution
4. **Consider Failover**: Use Route 53 failover routing for HA
5. **Application Retry Logic**: Implement retry logic in application for failed connections

### Better Approach:

1. **Use Single NLB**: Consolidate to one NLB with 3 target groups
2. **Application-Level HA**: Use Redis Sentinel or Cluster mode
3. **Direct Endpoint Access**: Application connects to all 3 endpoints directly
4. **Client-Side Load Balancing**: Use Redis client libraries with built-in load balancing

## Cost Comparison

| Approach | NLB Cost | Route 53 Cost | Total Monthly |
|----------|----------|--------------|---------------|
| **3 NLBs + Route 53** | ~$48 | ~$0.50 | ~$48.50 |
| **Single NLB** | ~$16 | $0 | ~$16 |
| **Savings** | - | - | **~$32/month** |

## Conclusion

While Route 53 weighted routing can work, it's **not ideal for Redis** due to:
- DNS caching issues
- Connection persistence
- Higher cost
- Limited effectiveness for Redis workloads

**Recommended**: Use a single NLB with application-level Redis Sentinel/Cluster configuration, or implement client-side load balancing.

