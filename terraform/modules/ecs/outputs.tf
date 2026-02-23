output "cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) that identifies the cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.wordpress.name
}

output "service_arn" {
  description = "The ARN of the ECS service"
  value       = aws_ecs_service.wordpress.id
}

output "task_definition_arn" {
  description = "The full ARN of the latest task definition revision"
  value       = aws_ecs_task_definition.wordpress.arn
}

output "task_definition_family" {
  description = "The family of the task definition"
  value       = aws_ecs_task_definition.wordpress.family
}

output "task_security_group_id" {
  description = "The ID of the security group assigned to ECS tasks (required by RDS for ingress rules)"
  value       = aws_security_group.ecs_tasks.id
}

output "log_group_name" {
  description = "The name of the CloudWatch log group where logs are sent"
  value       = aws_cloudwatch_log_group.ecs.name
}