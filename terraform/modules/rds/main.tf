# Module: rds
# Creates an RDS MySQL instance in private subnets with a dedicated
# security group that only allows traffic from ECS tasks.

# DB Subnet Group

resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-db-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for ${var.name_prefix} RDS"

  tags = { Name = "${var.name_prefix}-db-subnet-group" }
}

# Security Group — RDS
# Only accepts MySQL traffic from the ECS task security group.

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allows inbound from ECS tasks only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-rds-sg" }
}

resource "aws_security_group_rule" "rds_from_ecs" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = var.ecs_security_group_id
  description              = "MySQL from ECS tasks"
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound"
}

# RDS Instance

resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2  # Auto-scaling storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = var.db_multi_az
  publicly_accessible    = false
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.name_prefix}-mysql-final-snapshot"

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection     = false  # Set true for production
  apply_immediately       = false
  performance_insights_enabled = false

  tags = { Name = "${var.name_prefix}-mysql" }
}
