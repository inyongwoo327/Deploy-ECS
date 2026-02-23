output "endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS hostname (without port)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "security_group_id" {
  description = "Security group ID attached to RDS"
  value       = aws_security_group.rds.id
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}
