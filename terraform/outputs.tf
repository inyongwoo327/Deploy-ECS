# =============================================================================
# Root Outputs
# =============================================================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer — open this in your browser"
  value       = module.alb.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (used for Route 53 alias records)"
  value       = module.alb.zone_id
}

output "ecr_repository_url" {
  description = "ECR repository URL — use this in your Packer build vars"
  value       = module.ecr.repository_url
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint (host:port)"
  value       = module.rds.endpoint
  sensitive   = false
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs.service_name
}

output "wordpress_url" {
  description = "WordPress URL (HTTP via ALB)"
  value       = "http://${module.alb.dns_name}"
}

output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret holding RDS credentials"
  value       = module.secrets.secret_arn
  sensitive   = true
}
