# Prod Account - Single NLB Approach (RECOMMENDED)
# Creates ONE NLB with 3 target groups (one per Redis server)
# Cost: ~$16/month
# Best for: Most use cases, lower cost, simpler management

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
  # Prod Account (Joda) - Configure AWS credentials
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "redis_server_ips" {
  description = "List of on-premises Redis server IP addresses"
  type        = list(string)
  # Example: ["10.0.4.10", "10.0.4.11", "10.0.4.12"]
}

variable "redis_port" {
  description = "Redis server port"
  type        = number
  default     = 6379
}

variable "prod_vpc_id" {
  description = "VPC ID in Prod Account (10.2.0.0/16)"
  type        = string
}

variable "prod_subnet_ids" {
  description = "Subnet IDs for NLB in Prod VPC (should be able to reach on-premises via TGW)"
  type        = list(string)
}

variable "consumer_account_id" {
  description = "AWS Account ID of Joda-Toda-AWS account (consumer)"
  type        = string
}

variable "endpoint_service_name" {
  description = "Name for the VPC Endpoint Service"
  type        = string
  default     = "joda-redis-onprem-service"
}

# Data sources
data "aws_vpc" "prod_vpc" {
  id = var.prod_vpc_id
}

# Security Group for NLB
resource "aws_security_group" "nlb_sg" {
  name        = "redis-nlb-sg-single"
  description = "Security group for Redis NLB (single NLB approach)"
  vpc_id      = var.prod_vpc_id

  ingress {
    description = "Redis from VPC"
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.prod_vpc.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "redis-nlb-sg-single"
    Purpose = "Redis PrivateLink Service"
    Approach = "Single NLB"
  }
}

# Single Network Load Balancer
resource "aws_lb" "redis_nlb" {
  name               = "joda-redis-onprem-nlb-single"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.prod_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "joda-redis-onprem-nlb-single"
    Environment = "production"
    Purpose     = "Redis PrivateLink Service"
    Approach    = "Single NLB"
    Note        = "Reaches Redis via TGW → Connectivity Account → Direct Connect"
  }
}

# Target Groups - One for each Redis server
resource "aws_lb_target_group" "redis_targets" {
  count = length(var.redis_server_ips)

  name     = "redis-tg-${count.index + 1}"
  port     = var.redis_port
  protocol = "TCP"
  vpc_id   = var.prod_vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = var.redis_port
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 10
  }

  tags = {
    Name    = "redis-tg-${count.index + 1}"
    Purpose = "Redis PrivateLink Service"
  }
}

# Register targets (on-premises Redis servers)
resource "aws_lb_target_group_attachment" "redis_targets" {
  count = length(var.redis_server_ips)

  target_group_arn = aws_lb_target_group.redis_targets[count.index].arn
  target_id        = var.redis_server_ips[count.index]
  port             = var.redis_port
}

# Listeners - One for each target group
# Note: Using different ports (6379, 6380, 6381) because NLB can't have multiple listeners on same port
resource "aws_lb_listener" "redis_listeners" {
  count = length(aws_lb_target_group.redis_targets)

  load_balancer_arn = aws_lb.redis_nlb.arn
  port              = var.redis_port + count.index
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redis_targets[count.index].arn
  }
}

# Single VPC Endpoint Service
resource "aws_vpc_endpoint_service" "redis_service" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.redis_nlb.arn]
  
  # Use ARN format for allowed_principals (recommended by AWS Provider)
  allowed_principals = ["arn:aws:iam::${var.consumer_account_id}:root"]

  tags = {
    Name    = var.endpoint_service_name
    Purpose = "Redis PrivateLink Service for Joda-Toda-AWS"
    Approach = "Single NLB"
  }
}

# Outputs
output "vpc_endpoint_service_name" {
  description = "VPC Endpoint Service name (use this in Joda-Toda-AWS account)"
  value       = aws_vpc_endpoint_service.redis_service.service_name
}

output "vpc_endpoint_service_id" {
  description = "VPC Endpoint Service ID"
  value       = aws_vpc_endpoint_service.redis_service.id
}

output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.redis_nlb.dns_name
}

output "listener_ports" {
  description = "Ports exposed by listeners (for reference)"
  value = {
    for idx, listener in aws_lb_listener.redis_listeners :
    "redis-${idx + 1}" => listener.port
  }
}

output "application_note" {
  description = "How to use this in applications"
  value = <<-EOT
    IMPORTANT: Application should connect to all 3 VPC endpoints directly.
    
    The NLB exposes different ports (6379, 6380, 6381) but applications should use:
    - All 3 VPC endpoint DNS names
    - Port 6379 (standard Redis port)
    - Use Redis Sentinel/Cluster mode or client-side load balancing
    
    DO NOT use Route 53 weighted routing - use application-level load balancing instead.
  EOT
}

