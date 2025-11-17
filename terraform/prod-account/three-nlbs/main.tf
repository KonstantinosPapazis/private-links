# Prod Account - Three NLBs Approach (What Engineer Created)
# Creates THREE separate NLBs (one per Redis server)
# Cost: ~$48/month
# Use Case: If you need individual server access or Route 53 weighted routing

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
  description = "Subnet IDs for NLBs in Prod VPC (should be able to reach on-premises via TGW)"
  type        = list(string)
}

variable "consumer_account_id" {
  description = "AWS Account ID of Joda-Toda-AWS account (consumer)"
  type        = string
}

variable "endpoint_service_name_prefix" {
  description = "Prefix for VPC Endpoint Service names"
  type        = string
  default     = "joda-redis-onprem"
}

# Data sources
data "aws_vpc" "prod_vpc" {
  id = var.prod_vpc_id
}

# Security Groups for NLBs
resource "aws_security_group" "nlb_sg" {
  count = length(var.redis_server_ips)

  name        = "redis-nlb-sg-${count.index + 1}"
  description = "Security group for Redis NLB ${count.index + 1}"
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
    Name    = "redis-nlb-sg-${count.index + 1}"
    Purpose = "Redis PrivateLink Service"
    Approach = "Three NLBs"
    RedisServer = "redis-${count.index + 1}"
  }
}

# Three Network Load Balancers (one per Redis server)
resource "aws_lb" "redis_nlb" {
  count = length(var.redis_server_ips)

  name               = "joda-redis-onprem-nlb-${count.index + 1}"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.prod_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "joda-redis-onprem-nlb-${count.index + 1}"
    Environment = "production"
    Purpose     = "Redis PrivateLink Service"
    Approach    = "Three NLBs"
    RedisServer = "redis-${count.index + 1}"
    Note        = "Reaches Redis via TGW → Connectivity Account → Direct Connect"
  }
}

# Target Groups - One per NLB (one Redis server per target group)
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
    RedisServer = "redis-${count.index + 1}"
  }
}

# Register targets (one Redis server per target group)
resource "aws_lb_target_group_attachment" "redis_targets" {
  count = length(var.redis_server_ips)

  target_group_arn = aws_lb_target_group.redis_targets[count.index].arn
  target_id        = var.redis_server_ips[count.index]
  port             = var.redis_port
}

# Listeners - One per NLB (all on port 6379)
resource "aws_lb_listener" "redis_listeners" {
  count = length(aws_lb.redis_nlb)

  load_balancer_arn = aws_lb.redis_nlb[count.index].arn
  port              = var.redis_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redis_targets[count.index].arn
  }
}

# Three VPC Endpoint Services (one per NLB)
resource "aws_vpc_endpoint_service" "redis_service" {
  count = length(aws_lb.redis_nlb)

  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.redis_nlb[count.index].arn]
  
  # Use ARN format for allowed_principals (recommended by AWS Provider)
  allowed_principals = ["arn:aws:iam::${var.consumer_account_id}:root"]

  tags = {
    Name    = "${var.endpoint_service_name_prefix}-service-${count.index + 1}"
    Purpose = "Redis PrivateLink Service for Joda-Toda-AWS"
    Approach = "Three NLBs"
    RedisServer = "redis-${count.index + 1}"
  }
}

# Outputs
output "vpc_endpoint_service_names" {
  description = "VPC Endpoint Service names (use these in Joda-Toda-AWS account)"
  value       = aws_vpc_endpoint_service.redis_service[*].service_name
}

output "vpc_endpoint_service_ids" {
  description = "VPC Endpoint Service IDs"
  value       = aws_vpc_endpoint_service.redis_service[*].id
}

output "nlb_dns_names" {
  description = "DNS names of the NLBs"
  value       = aws_lb.redis_nlb[*].dns_name
}

output "nlb_arns" {
  description = "ARNs of the NLBs"
  value       = aws_lb.redis_nlb[*].arn
}

output "route53_note" {
  description = "Note about Route 53 usage"
  value = <<-EOT
    WARNING: Route 53 weighted routing is NOT recommended for Redis due to:
    - DNS caching issues
    - Persistent connections
    - Uneven load distribution
    
    RECOMMENDATION: Use application-level load balancing (Redis Sentinel/Cluster) instead.
    
    If you must use Route 53, see: terraform/route53-weighted-routing/
  EOT
}

