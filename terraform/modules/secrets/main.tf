# Module: secrets
# Generates a random DB password and stores all RDS credentials in
# AWS Secrets Manager. 
# via the `secrets` field (valueFrom) — no credentials in env vars or code.

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/db-credentials"
  description             = "RDS MySQL credentials for ${var.name_prefix}"
  recovery_window_in_days = 7

  tags = { Name = "${var.name_prefix}-db-secret" }
}
