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

source "docker" "wordpress" {
  image  = "php:8.2-apache"
  commit = true

  # run a container to allow provisioning
  run_command = ["-d", "-i", "-t", "--name", "packer-wordpress", "{{.Image}}", "/bin/bash"]

  changes = [
    "EXPOSE 80",
    "ENV WORDPRESS_DB_HOST=''",
    "ENV WORDPRESS_DB_USER=''",
    "ENV WORDPRESS_DB_PASSWORD=''",
    "ENV WORDPRESS_DB_NAME=wordpress",
    "ENV WORDPRESS_TABLE_PREFIX=wp_",
    "WORKDIR /var/www/html",
    "CMD [\"apache2-foreground\"]"
  ]
}

build {
  name    = "wordpress-ecs"
  sources = ["source.docker.wordpress"]

  # Run Ansible playbook inside the container
  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/playbook.yaml"

    extra_arguments = [
      "--extra-vars", "wordpress_version=${var.wordpress_version}",
      "--connection", "docker",
      "-vv"
    ]

    # Ansible needs the container name to connect via docker
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3"
    ]
  }

  # Tag the committed image for ECR
  post-processor "docker-tag" {
    repository = "${local.ecr_registry}/${local.ecr_repo}"
    tags       = [local.effective_tag, "latest"]
  }

  # Push to ECR
  post-processor "docker-push" {
    ecr_login    = true
    aws_profile  = ""
    login_server = local.ecr_registry
  }
}
