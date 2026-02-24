packer {
  required_version = ">= 1.10.0"

  required_plugins {
    docker = {
      version = ">= 1.0.9"
      source  = "github.com/hashicorp/docker"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "wordpress_version" {
  description = "WordPress version to install"
  type        = string
  default     = "6.4.3"
}

variable "aws_region" {
  description = "AWS region where ECR lives"
  type        = string
  default     = "eu-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID for ECR URL construction"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag (defaults to wordpress version)"
  type        = string
  default     = ""
}

locals {
  effective_tag = var.image_tag != "" ? var.image_tag : var.wordpress_version
  ecr_registry  = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  ecr_repo      = "wordpress-ecs"
}