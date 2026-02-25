# 1. Define the random generator resource
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# 2. Reference it in your secret
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/db-credentials-${random_id.secret_suffix.hex}"
  description             = "RDS MySQL credentials for ${var.name_prefix}"
  recovery_window_in_days = 0 

  tags = { Name = "${var.name_prefix}-db-secret" }
}

# 3. Update the secret version
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
    # Ensure this is linked to your RDS output in root main.tf
    host     = var.db_host
    port     = 3306
  })
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}