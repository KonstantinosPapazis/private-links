# Route 53 Weighted Routing Configuration
# This is for reference - shows how to configure Route 53 weighted routing
# for 3 separate PrivateLink endpoints

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
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dev_vpc_id" {
  description = "Dev VPC ID"
  type        = string
}

variable "vpc_endpoint_ids" {
  description = "List of VPC endpoint IDs (3 endpoints)"
  type        = list(string)
}

variable "vpc_endpoint_dns_names" {
  description = "List of VPC endpoint DNS names"
  type        = list(string)
}

variable "vpc_endpoint_hosted_zone_ids" {
  description = "List of VPC endpoint hosted zone IDs"
  type        = list(string)
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "dns_name" {
  description = "DNS name for Redis (e.g., redis.joda-toda.internal)"
  type        = string
  default     = "redis.joda-toda.internal"
}

variable "dns_zone_name" {
  description = "Private hosted zone name"
  type        = string
  default     = "joda-toda.internal"
}

# Private Hosted Zone
resource "aws_route53_zone" "internal" {
  name = var.dns_zone_name
  
  vpc {
    vpc_id = var.dev_vpc_id
  }

  tags = {
    Name = "joda-toda-internal-zone"
    Purpose = "Redis PrivateLink DNS"
  }
}

# Health Checks for each endpoint
resource "aws_route53_health_check" "redis_endpoints" {
  count = length(var.vpc_endpoint_ids)

  fqdn              = var.vpc_endpoint_dns_names[count.index]
  port              = var.redis_port
  type              = "TCP"
  failure_threshold = 3
  request_interval  = 30
  measure_latency   = true

  tags = {
    Name = "redis-endpoint-${count.index + 1}-health"
  }
}

# Weighted Route 53 Records
resource "aws_route53_record" "redis_weighted" {
  count = length(var.vpc_endpoint_ids)

  zone_id = aws_route53_zone.internal.zone_id
  name    = var.dns_name
  type    = "A"
  
  set_identifier = "redis-endpoint-${count.index + 1}"
  
  weighted_routing_policy {
    weight = count.index == 2 ? 34 : 33  # 33, 33, 34
  }
  
  health_check_id = aws_route53_health_check.redis_endpoints[count.index].id
  
  alias {
    name                   = var.vpc_endpoint_dns_names[count.index]
    zone_id                = var.vpc_endpoint_hosted_zone_ids[count.index]
    evaluate_target_health = true
  }

  ttl = 60  # Low TTL to reduce DNS caching impact
}

# Outputs
output "dns_name" {
  description = "DNS name to use for Redis connections"
  value       = "${var.dns_name}.${var.dns_zone_name}"
}

output "zone_id" {
  description = "Route 53 zone ID"
  value       = aws_route53_zone.internal.zone_id
}

output "health_check_ids" {
  description = "Health check IDs"
  value       = aws_route53_health_check.redis_endpoints[*].id
}

output "usage_note" {
  description = "Important notes about using Route 53 weighted routing with Redis"
  value = <<-EOT
    IMPORTANT CONSIDERATIONS:
    
    1. DNS Caching: Redis clients cache DNS lookups. Weighted routing only affects NEW connections.
    2. Connection Persistence: Redis maintains persistent connections. DNS changes don't affect active connections.
    3. Health Checks: Route 53 health checks are DNS-level, not Redis-level.
    4. TTL: Low TTL (60s) helps but doesn't solve caching issues completely.
    
    RECOMMENDATION: Consider using Redis Sentinel/Cluster mode or application-level load balancing instead.
    
    To use this DNS name:
    redis-cli -h ${var.dns_name}.${var.dns_zone_name} -p ${var.redis_port}
  EOT
}

