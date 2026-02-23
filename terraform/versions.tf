terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.85"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # backend "s3" {
  #   bucket         = "yoeng327-terraform-state-bucket"
  #   key            = "wordpress-ecs/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}