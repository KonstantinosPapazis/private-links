# Joda Company - Current Architecture Diagram

## Network Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         JODA COMPANY                                        │
│                      On-Premises Environment                                │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                    On-Premises Systems                            │    │
│  │                                                                    │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐         │    │
│  │  │ System 1 │  │ System 2 │  │ System 3 │  │  Redis   │         │    │
│  │  │          │  │          │  │          │  │ (3 nodes) │         │    │
│  │  │ 10.0.1.x │  │ 10.0.2.x │  │ 10.0.3.x │  │ 10.0.4.x │         │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘         │    │
│  │                                                                    │    │
│  │                    On-Premises Network                             │    │
│  │                    (10.0.0.0/16)                                  │    │
│  └────────────────────────────┬───────────────────────────────────────┘    │
│                               │                                            │
│                    ┌──────────▼──────────┐                                 │
│                    │   Direct Connect     │                                 │
│                    │   (DX Connection)     │                                 │
│                    └──────────┬──────────┘                                 │
└───────────────────────────────┼────────────────────────────────────────────┘
                                │
                                │ Direct Connect
                                │ (Private VIF)
                                │
┌───────────────────────────────▼────────────────────────────────────────────┐
│                    AWS CONNECTIVITY ACCOUNT                                 │
│                    (Network Hub Account)                                    │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                         VPC-Connectivity                           │    │
│  │                      (10.1.0.0/16)                                │    │
│  │                                                                    │    │
│  │  ┌────────────────────────────────────────────────────────────┐   │    │
│  │  │         Direct Connect Gateway (DXGW)                      │   │    │
│  │  │         - Receives on-prem traffic                         │   │    │
│  │  │         - Routes to/from on-premises                       │   │    │
│  │  └────────────────────┬───────────────────────────────────────┘   │    │
│  │                       │                                            │    │
│  │  ┌────────────────────▼───────────────────────────────────────┐   │    │
│  │  │              Transit Gateway (TGW)                         │   │    │
│  │  │              - Central network hub                         │   │    │
│  │  │              - Routes between VPCs                         │   │    │
│  │  │              - Connects to Prod Account                    │   │    │
│  │  └────────────────────┬───────────────────────────────────────┘   │    │
│  │                       │                                            │    │
│  │                       │ Transit Gateway Attachment                │    │
│  │                       │ (VPC Attachment)                           │    │
│  └───────────────────────┼────────────────────────────────────────────┘    │
│                           │                                                  │
│                           │ Transit Gateway                                  │
│                           │ (Cross-Account)                                  │
│                           │                                                  │
└───────────────────────────┼──────────────────────────────────────────────────┘
                            │
                            │ Transit Gateway
                            │ Resource Share (RAM)
                            │
┌───────────────────────────▼──────────────────────────────────────────────────┐
│                    AWS PROD ACCOUNT                                           │
│                    (Services Account)                                         │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │                         VPC-Prod                                  │     │
│  │                      (10.2.0.0/16)                                │     │
│  │                                                                    │     │
│  │  ┌────────────────────────────────────────────────────────────┐   │     │
│  │  │         Transit Gateway Attachment                        │   │     │
│  │  │         (Connected to Connectivity Account TGW)           │   │     │
│  │  └────────────────────┬───────────────────────────────────────┘   │     │
│  │                       │                                            │     │
│  │  ┌────────────────────▼───────────────────────────────────────┐   │     │
│  │  │              Route Tables                                  │   │     │
│  │  │              - Routes to on-prem (via TGW)                │   │     │
│  │  │              - Routes to Connectivity VPC                 │   │     │
│  │  └────────────────────┬───────────────────────────────────────┘   │     │
│  │                       │                                            │     │
│  │  ┌────────────────────▼───────────────────────────────────────┐   │     │
│  │  │              Application Services                           │   │     │
│  │  │                                                             │   │     │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │   │     │
│  │  │  │   App 1  │  │   App 2  │  │   App 3  │  │   App 4  │  │   │     │
│  │  │  │          │  │          │  │          │  │          │  │   │     │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │   │     │
│  │  │                                                             │   │     │
│  │  │  All services can access on-premises systems via:          │   │     │
│  │  │  Prod VPC → TGW Attachment → Connectivity TGW →            │   │     │
│  │  │  DXGW → Direct Connect → On-Premises                       │   │     │
│  │  └─────────────────────────────────────────────────────────────┘   │     │
│  └────────────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. On-Premises Environment
- **Location**: Joda Company datacenter
- **Network**: 10.0.0.0/16
- **Systems**: Various on-prem systems including Redis (3 nodes)
- **Connection**: Direct Connect to AWS Connectivity Account

### 2. AWS Connectivity Account (Hub Account)
- **Purpose**: Network hub for connectivity
- **Components**:
  - **Direct Connect Gateway (DXGW)**: Receives on-prem traffic
  - **VPC-Connectivity**: VPC in connectivity account (10.1.0.0/16)
  - **Transit Gateway (TGW)**: Central routing hub
- **Function**: Routes traffic between on-prem and AWS accounts

### 3. AWS Prod Account (Services Account)
- **Purpose**: Hosts all application services
- **Components**:
  - **VPC-Prod**: Production VPC (10.2.0.0/16)
  - **Transit Gateway Attachment**: Connects to Connectivity Account TGW
  - **Route Tables**: Configured to route to on-prem via TGW
  - **Application Services**: All production workloads
- **Access**: Can reach all on-premises systems via TGW routing

## Traffic Flow

### On-Premises → Prod Account
```
On-Prem System → Direct Connect → Connectivity Account DXGW → 
Connectivity VPC → Transit Gateway → Prod Account TGW Attachment → 
Prod VPC → Application Services
```

### Prod Account → On-Premises
```
Prod App → Prod VPC → TGW Attachment → Transit Gateway → 
Connectivity VPC → DXGW → Direct Connect → On-Prem System
```

## Network Addressing

| Component | CIDR Block | Purpose |
|-----------|------------|---------|
| On-Premises | 10.0.0.0/16 | Company datacenter network |
| Connectivity VPC | 10.1.0.0/16 | Network hub VPC |
| Prod VPC | 10.2.0.0/16 | Production services VPC |

## Verification Checklist

- [x] Direct Connect connects on-prem to Connectivity Account
- [x] Transit Gateway exists in Connectivity Account
- [x] Prod Account has TGW Attachment to Connectivity Account TGW
- [x] Route tables configured for on-prem routing
- [x] Prod Account services can reach on-prem systems
- [x] On-prem systems can reach Prod Account services (if needed)

## Notes

- **Transit Gateway Sharing**: Prod Account accesses TGW via AWS Resource Access Manager (RAM)
- **Routing**: Route tables in both accounts must be configured to allow traffic flow
- **Security**: Security groups and NACLs control access at VPC level
- **High Availability**: Direct Connect typically has redundant connections

