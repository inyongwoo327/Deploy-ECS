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
  description = "AWS account ID"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = ""
}

variable "ecr_repository_name" {
  description = "The name of the ECR repository"
  type        = string
  default     = "wordpress-ecs-dev" # Fallback default
}

locals {
  effective_tag = var.image_tag != "" ? var.image_tag : var.wordpress_version
  ecr_registry  = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  ecr_repo      = var.ecr_repository_name
}

source "docker" "wordpress" {
  image  = "php:8.2-apache"
  commit = true
  run_command = ["-d", "-i", "-t", "--name", "packer-wordpress", "{{.Image}}", "/bin/bash"]

  changes = [
    "EXPOSE 80",
    "WORKDIR /var/www/html",
    "CMD [\"apache2-foreground\"]"
  ]
}

build {
  name    = "wordpress-ecs"
  sources = ["source.docker.wordpress"]

  # Install Python, Ansible, and the system-level libraries required by the Ansible role
  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get install -y python3 ansible libicu-dev libpng-dev libjpeg-dev libfreetype6-dev libzip-dev",
      "mkdir -p /tmp/ansible-local"
    ]
  }

  # Execute Ansible locally inside the container
  provisioner "ansible-local" {
    playbook_file   = "${path.root}/ansible/playbook.yaml"
    role_paths      = ["${path.root}/ansible/roles/wordpress"]
    
    extra_arguments = [
      "--extra-vars", "wordpress_version=${var.wordpress_version}",
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "-v" 
    ]
  }

  # Chain the post-processors together
  post-processors {
    post-processor "docker-tag" {
      repository = "${local.ecr_registry}/${local.ecr_repo}"
      tags       = [local.effective_tag, "latest"]
    }

    post-processor "docker-push" {
      ecr_login    = true
      login_server = local.ecr_registry
    }
  }
}