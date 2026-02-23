variable "name_prefix" { type = string }
variable "account_id"   { type = string }
variable "aws_region"   { type = string }
variable "ecr_repo_arn" { type = string }
variable "secret_arns"  { type = list(string) }
