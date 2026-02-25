variable "name_prefix" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_host" {
  description = "The RDS instance endpoint"
  type        = string
  default     = "" # Optional default
}