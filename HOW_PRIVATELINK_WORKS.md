# How AWS PrivateLink Works: Single NLB with Multiple VPC Endpoints

## Architecture Overview

This document explains how **one Network Load Balancer (NLB)** in the **service account** (Prod Account) works with **one VPC Endpoint Service** and **three VPC Endpoints** in the **consumer account** (Joda-Toda-AWS).

## Key Components

### Service Account (Prod Account)

1. **One Network Load Balancer (NLB)**
   - Internal NLB in Prod VPC
   - Can reach on-premises Redis servers via Transit Gateway

2. **Three Target Groups** (attached to the single NLB)
   - Target Group 1 → Redis Server 1 (10.0.4.10:6379)
   - Target Group 2 → Redis Server 2 (10.0.4.11:6379)
   - Target Group 3 → Redis Server 3 (10.0.4.12:6379)

3. **Three Listeners** (on the single NLB)
   - Listener 1: Port 6379 → Target Group 1
   - Listener 2: Port 6380 → Target Group 2
   - Listener 3: Port 6381 → Target Group 3
   - **Note**: Different ports are required because an NLB cannot have multiple listeners on the same port

4. **One VPC Endpoint Service**
   - Created from the single NLB
   - Shares the NLB with the consumer account
   - Service Name: `com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx`

### Consumer Account (Joda-Toda-AWS)

1. **Three VPC Endpoints** (Interface endpoints)
   - All three connect to the **same** VPC Endpoint Service
   - Created in Dev VPC
   - Distributed across multiple Availability Zones for HA
   - Each endpoint gets its own ENI (Elastic Network Interface) with a private IP

## How It Works: Step by Step

### 1. Service Account Setup

```
┌─────────────────────────────────────────────────┐
│  Prod Account (Service Provider)                │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  Network Load Balancer (Single)          │  │
│  │                                           │  │
│  │  Listener 1: Port 6379 → TG1 → Redis-1 │  │
│  │  Listener 2: Port 6380 → TG2 → Redis-2  │  │
│  │  Listener 3: Port 6381 → TG3 → Redis-3  │  │
│  └──────────────┬───────────────────────────┘  │
│                 │                                │
│  ┌──────────────▼───────────────────────────┐  │
│  │  VPC Endpoint Service                    │  │
│  │  (Created from the NLB)                  │  │
│  │  Service Name: vpce-svc-xxxxx            │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### 2. Consumer Account Setup

```
┌─────────────────────────────────────────────────┐
│  Joda-Toda-AWS Account (Consumer)               │
│                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────┐│
│  │ VPC Endpoint │  │ VPC Endpoint │  │ VPC    ││
│  │     1        │  │     2        │  │Endpoint││
│  │              │  │              │  │   3    ││
│  │ ENI: 10.3.x │  │ ENI: 10.3.y  │  │ ENI:   ││
│  │              │  │              │  │ 10.3.z ││
│  └──────┬───────┘  └──────┬───────┘  └───┬────┘│
│         │                 │              │     │
│         └─────────────────┴──────────────┘     │
│                    │                            │
│         All connect to same service:            │
│         vpce-svc-xxxxx                          │
└─────────────────────────────────────────────────┘
```

### 3. Connection Flow

When an application in Dev VPC connects to Redis:

```
Application (Dev VPC)
    ↓
Connects to: vpce-xxx.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com
    ↓
VPC Endpoint 1 (or 2, or 3) - AWS routes to one of them
    ↓
AWS PrivateLink (encrypted tunnel over AWS backbone)
    ↓
VPC Endpoint Service (Prod Account)
    ↓
Network Load Balancer
    ↓
Target Group (one of three)
    ↓
On-Premises Redis Server (via TGW → Direct Connect)
```

## Important Details

### Why Three VPC Endpoints?

Even though there's only **one VPC Endpoint Service**, you create **three VPC Endpoints** for:

1. **High Availability**: Each endpoint is in a different Availability Zone
2. **Load Distribution**: AWS automatically distributes connections across endpoints
3. **Fault Tolerance**: If one endpoint fails, others continue working
4. **Redis Cluster Support**: Applications can connect to all three endpoints for Redis Sentinel/Cluster mode

### How Does AWS Route Traffic?

When you create multiple VPC Endpoints connecting to the same VPC Endpoint Service:

- AWS **automatically load balances** connections across all endpoints
- Each endpoint gets its own ENI (Elastic Network Interface) with a private IP
- DNS resolution returns different IPs based on availability and load
- Connections are distributed across AZs for resilience

### Port Mapping Challenge

**Important**: The NLB uses different ports (6379, 6380, 6381) because:
- An NLB cannot have multiple listeners on the same port
- Each listener forwards to a different target group (different Redis server)

**However**, applications should:
- Connect to all **three VPC endpoint DNS names**
- Use port **6379** (standard Redis port) on all connections
- The VPC Endpoint Service handles the port mapping internally

### Application Configuration

Your Redis application should connect like this:

```python
# Example: Python Redis client
import redis

# Connect to all three VPC endpoints
redis_endpoints = [
    'vpce-xxx.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com:6379',
    'vpce-yyy.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com:6379',
    'vpce-zzz.vpce-svc-xxxxx.vpce.us-east-1.vpce.amazonaws.com:6379'
]

# Use Redis Sentinel or Cluster mode
from redis.sentinel import Sentinel
sentinel = Sentinel(redis_endpoints, socket_timeout=0.1)
master = sentinel.master_for('mymaster', socket_timeout=0.1)
```

**Key Point**: All three endpoints connect to the **same VPC Endpoint Service**, which routes to the **same NLB**, which then routes to different Redis servers based on the target group.

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  On-Premises Redis Servers                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                    │
│  │ Redis-1  │  │ Redis-2  │  │ Redis-3  │                    │
│  │ 10.0.4.10│  │ 10.0.4.11│  │ 10.0.4.12│                    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                    │
└───────┼─────────────┼─────────────┼────────────────────────────┘
        │             │             │
        └─────────────┴─────────────┘
                    │
        Direct Connect → TGW → Prod VPC
                    │
┌───────────────────▼───────────────────────────────────────────┐
│  Prod Account                                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Network Load Balancer (Single)                         │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │ │
│  │  │ TG1      │  │ TG2      │  │ TG3      │            │ │
│  │  │→Redis-1  │  │→Redis-2  │  │→Redis-3  │            │ │
│  │  └──────────┘  └──────────┘  └──────────┘            │ │
│  └───────────────────────┬────────────────────────────────┘ │
│                          │                                   │
│  ┌───────────────────────▼────────────────────────────────┐ │
│  │  VPC Endpoint Service (Single)                         │ │
│  │  Service Name: vpce-svc-xxxxx                          │ │
│  └────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                    │
        AWS PrivateLink (encrypted tunnel)
                    │
┌───────────────────▼───────────────────────────────────────────┐
│  Joda-Toda-AWS Account (Dev VPC)                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ VPC      │  │ VPC      │  │ VPC      │                  │
│  │Endpoint 1│  │Endpoint 2│  │Endpoint 3│                  │
│  │(AZ-1a)   │  │(AZ-1b)   │  │(AZ-1c)   │                  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                  │
│       │             │             │                          │
│       └─────────────┴─────────────┘                          │
│                    │                                          │
│  ┌─────────────────▼──────────────────────────────────────┐ │
│  │  Application connects to all 3 endpoints                │ │
│  │  Uses Redis Sentinel/Cluster mode                     │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

## Summary

**How it works**:

1. **One NLB** in Prod Account has **3 target groups** (one per Redis server)
2. **One VPC Endpoint Service** exposes the NLB to consumers
3. **Three VPC Endpoints** in consumer account all connect to the **same service**
4. AWS automatically load balances connections across the three endpoints
5. Applications connect to all three endpoints for HA and use Redis Sentinel/Cluster

**Key Benefits**:
- ✅ Lower cost (~$16/month for NLB vs ~$48/month for 3 NLBs)
- ✅ Simpler architecture (one service to manage)
- ✅ High availability (endpoints in multiple AZs)
- ✅ Works with Redis Sentinel/Cluster mode

**Important**: This is **NOT** VPC Links (API Gateway concept). This is AWS PrivateLink using:
- **VPC Endpoint Service** (service provider side)
- **VPC Endpoints** (consumer side)

