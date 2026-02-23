variable "name_prefix"             { type = string }
variable "aws_region"              { type = string }
variable "vpc_id"                  { type = string }
variable "private_subnet_ids"      { type = list(string) }
variable "alb_security_group_id"   { type = string }
variable "alb_target_group_arn"    { type = string }
variable "task_execution_role_arn" { type = string }
variable "task_role_arn"           { type = string }
variable "ecr_image_url"           { type = string }
variable "secret_arn"              { type = string }
variable "db_host"                 { type = string }

variable "ecs_task_cpu" {
  type    = number
  default = 512
}

variable "ecs_task_memory" {
  type    = number
  default = 1024
}

variable "ecs_desired_count" {
  type    = number
  default = 1
}

variable "ecs_min_capacity" {
  type    = number
  default = 1
}

variable "ecs_max_capacity" {
  type    = number
  default = 4
}

variable "wordpress_debug" {
  type    = bool
  default = false
}

variable "wordpress_force_ssl" {
  type    = bool
  default = false
}
