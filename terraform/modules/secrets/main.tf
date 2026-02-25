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
  name                    = "${var.name_prefix}/db-credentials-${random_id.secret_suffix.hex}"
  description             = "RDS MySQL credentials for ${var.name_prefix}"
  recovery_window_in_days = 0

  tags = { Name = "${var.name_prefix}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
    host     = ""   # updated after RDS is created
    port     = 3306
  })
}
