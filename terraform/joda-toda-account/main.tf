# Joda-Toda-AWS Account - Dev VPC
# Creates VPC Endpoints to connect to Redis PrivateLink service
# Only Dev VPC needs PrivateLink access (Stage/Prod are on Toda network)

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"  # Supports AWS Provider 5.x and 6.x (latest: 6.20)
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  # Joda-Toda-AWS Account
  # Assume this is configured via AWS credentials
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dev_vpc_id" {
  description = "Dev VPC ID where VPC endpoints will be created (10.3.0.0/16)"
  type        = string
}

variable "dev_subnet_ids" {
  description = "Subnet IDs in Dev VPC for VPC endpoints (at least 2 in different AZs for HA)"
  type        = list(string)
}

variable "vpc_endpoint_service_name" {
  description = "VPC Endpoint Service name from Prod Account (for single NLB approach)"
  type        = string
  # Example: com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef
  # Get this from Prod Account after creating the endpoint service
  # For single NLB: use one service name
  # For three NLBs: leave empty and use vpc_endpoint_service_names instead
  default     = ""
}

variable "vpc_endpoint_service_names" {
  description = "List of VPC Endpoint Service names (for three NLBs approach)"
  type        = list(string)
  default     = []
  # Example: ["com.amazonaws.vpce.us-east-1.vpce-svc-xxx", "com.amazonaws.vpce.us-east-1.vpce-svc-yyy", "com.amazonaws.vpce.us-east-1.vpce-svc-zzz"]
}

variable "redis_port" {
  description = "Redis server port"
  type        = number
  default     = 6379
}

variable "number_of_endpoints" {
  description = "Number of VPC endpoints to create (one per Redis server)"
  type        = number
  default     = 3
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Data sources
data "aws_vpc" "dev_vpc" {
  id = var.dev_vpc_id
}

# Security Group for VPC Endpoints
resource "aws_security_group" "redis_endpoint_sg" {
  name        = "redis-privatelink-endpoint-sg-${var.environment}"
  description = "Security group for Redis PrivateLink VPC endpoints in Dev VPC"
  vpc_id      = var.dev_vpc_id

  ingress {
    description = "Redis from Dev VPC"
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.dev_vpc.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "redis-privatelink-endpoint-sg-${var.environment}"
    Environment = var.environment
    Purpose     = "Redis PrivateLink Access"
  }
}

# Determine which approach to use
locals {
  # Use three NLBs approach if service names list is provided
  use_three_nlbs = length(var.vpc_endpoint_service_names) > 0
  # Use single NLB approach if single service name is provided
  use_single_nlb = var.vpc_endpoint_service_name != ""
  
  # Determine number of endpoints and service names
  endpoint_count = local.use_three_nlbs ? length(var.vpc_endpoint_service_names) : var.number_of_endpoints
  service_names = local.use_three_nlbs ? var.vpc_endpoint_service_names : [for i in range(var.number_of_endpoints) : var.vpc_endpoint_service_name]
}

# VPC Endpoints - One for each Redis server
resource "aws_vpc_endpoint" "redis_endpoints" {
  count = local.endpoint_count

  vpc_id              = var.dev_vpc_id
  service_name        = local.service_names[count.index]
  vpc_endpoint_type   = "Interface"
  subnet_ids           = var.dev_subnet_ids
  security_group_ids   = [aws_security_group.redis_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "redis-endpoint-${count.index + 1}-${var.environment}"
    Environment = var.environment
    Purpose     = "Redis PrivateLink Access"
    RedisServer = "redis-${count.index + 1}"
    Approach    = local.use_three_nlbs ? "Three NLBs" : "Single NLB"
  }
}

# Outputs
output "vpc_endpoint_ids" {
  description = "IDs of the VPC endpoints"
  value       = aws_vpc_endpoint.redis_endpoints[*].id
}

output "vpc_endpoint_dns_names" {
  description = "DNS names of the VPC endpoints (use these to connect to Redis)"
  value       = aws_vpc_endpoint.redis_endpoints[*].dns_entry[0].dns_name
}

output "vpc_endpoint_ips" {
  description = "Private IP addresses of the VPC endpoints"
  value       = aws_vpc_endpoint.redis_endpoints[*].network_interface_ids
}

output "connection_acceptance_required" {
  description = "IMPORTANT: These endpoints require acceptance in the Prod Account"
  value       = "Accept connections in Prod Account: VPC → Endpoint Services → [Service Name] → Endpoint Connections"
}

output "redis_connection_info" {
  description = "Redis connection information for applications"
  value = {
    endpoints = aws_vpc_endpoint.redis_endpoints[*].dns_entry[0].dns_name
    port      = var.redis_port
    note      = "Connect to all 3 endpoints for high availability"
  }
}

