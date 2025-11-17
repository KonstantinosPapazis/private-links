# Joda Company - Current Architecture (One Page)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         JODA COMPANY - ON-PREMISES                          │
│                                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ System 1 │  │ System 2 │  │ System 3 │  │  Redis   │                  │
│  │          │  │          │  │          │  │ (3 nodes) │                  │
│  │10.0.1.x  │  │10.0.2.x  │  │10.0.3.x  │  │10.0.4.x  │                  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘                  │
│                                                                              │
│                    On-Premises Network (10.0.0.0/16)                        │
│                                                                              │
│                            ┌──────────────┐                                 │
│                            │ Direct Connect│                                 │
│                            │   (DX Link)   │                                 │
│                            └───────┬───────┘                                 │
└────────────────────────────────────┼─────────────────────────────────────────┘
                                     │
                                     │ Direct Connect Private VIF
                                     │
┌────────────────────────────────────▼─────────────────────────────────────────┐
│              AWS CONNECTIVITY ACCOUNT (Network Hub)                          │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │                    VPC-Connectivity (10.1.0.0/16)                 │     │
│  │                                                                    │     │
│  │         ┌──────────────────────────────────────┐                   │     │
│  │         │   Direct Connect Gateway (DXGW)     │                   │     │
│  │         │   • Receives on-prem traffic        │                   │     │
│  │         │   • Routes to/from on-premises      │                   │     │
│  │         └──────────────┬──────────────────────┘                   │     │
│  │                        │                                           │     │
│  │         ┌──────────────▼──────────────────────┐                   │     │
│  │         │      Transit Gateway (TGW)         │                   │     │
│  │         │   • Central network routing hub    │                   │     │
│  │         │   • Cross-account connectivity     │                   │     │
│  │         └──────────────┬──────────────────────┘                   │     │
│  └────────────────────────┼───────────────────────────────────────────┘     │
│                           │                                                  │
│                           │ Transit Gateway                                  │
│                           │ (Shared via RAM)                                 │
└───────────────────────────┼──────────────────────────────────────────────────┘
                             │
                             │ Transit Gateway Attachment
                             │
┌─────────────────────────────▼────────────────────────────────────────────────┐
│                    AWS PROD ACCOUNT (Services)                               │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │                    VPC-Prod (10.2.0.0/16)                         │     │
│  │                                                                    │     │
│  │         ┌──────────────────────────────────────┐                   │     │
│  │         │   Transit Gateway Attachment         │                   │     │
│  │         │   (Connected to Connectivity TGW)    │                   │     │
│  │         └──────────────┬───────────────────────┘                   │     │
│  │                        │                                           │     │
│  │         ┌──────────────▼───────────────────────┐                   │     │
│  │         │         Route Tables                 │                   │     │
│  │         │   • Routes to on-prem (via TGW)     │                   │     │
│  │         │   • Routes to Connectivity VPC       │                   │     │
│  │         └──────────────┬───────────────────────┘                   │     │
│  │                        │                                           │     │
│  │         ┌──────────────▼───────────────────────┐                   │     │
│  │         │      Application Services             │                   │     │
│  │         │                                       │                   │     │
│  │         │  ┌────┐  ┌────┐  ┌────┐  ┌────┐    │                   │     │
│  │         │  │App1│  │App2│  │App3│  │App4│    │                   │     │
│  │         │  └────┘  └────┘  └────┘  └────┘    │                   │     │
│  │         │                                       │                   │     │
│  │         │  ✅ All services can access          │                   │     │
│  │         │     on-premises systems via TGW      │                   │     │
│  │         └───────────────────────────────────────┘                   │     │
│  └────────────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow

**Prod Account → On-Premises:**
```
Prod App → VPC-Prod → TGW Attachment → Transit Gateway (Connectivity) → 
DXGW → Direct Connect → On-Prem System
```

**On-Premises → Prod Account:**
```
On-Prem System → Direct Connect → DXGW → Transit Gateway → 
TGW Attachment → VPC-Prod → Prod App
```

## Key Points

✅ **Direct Connect**: On-premises connected to Connectivity Account  
✅ **Transit Gateway**: Located in Connectivity Account, shared with Prod Account  
✅ **Prod Account Access**: All services can reach on-premises via TGW routing  
✅ **Network Isolation**: Each account has its own VPC with separate CIDR blocks  

## Network Addressing

- **On-Premises**: 10.0.0.0/16
- **Connectivity VPC**: 10.1.0.0/16  
- **Prod VPC**: 10.2.0.0/16

