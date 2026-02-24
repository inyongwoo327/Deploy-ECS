output "secret_arn" {
  description = "The ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_id" {
  description = "The ID (name) of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db.id
}

output "db_password" {
  description = "Generated DB password passed to the RDS module"
  value       = random_password.db.result
  sensitive   = true # Needs to prevent the password from printing in your terminal
}