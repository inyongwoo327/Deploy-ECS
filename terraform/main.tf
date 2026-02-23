# Root Module — WordPress on ECS
# Includes: VPC, ECR, Secrets, RDS, IAM, ALB, ECS modules.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  name_prefix = "${var.project_name}-${var.environment}"
}
