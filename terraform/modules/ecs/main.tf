# Module: ECS
# Creates the following resources:
#   (1) ECS cluster
#   (2) CloudWatch Log Group
#   (3) ECS Task Definition for WordPress container
#   (4) ECS Security Group
#   (5) ECS Fargate Service
#   (6) Application Auto Scaling (CPU-based)

# ECS Cluster

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# CloudWatch Log Group

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = 30
  tags              = { Name = "${var.name_prefix}-ecs-logs" }
}

# Security Group — ECS Tasks
# Allow inbound from ALB only. Then, allow all outbound (for RDS and ECR pull).

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-ecs-tasks-sg"
  description = "ECS tasks — allow inbound from ALB, outbound unrestricted"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-ecs-tasks-sg" }
}

resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks.id
  source_security_group_id = var.alb_security_group_id
  description              = "HTTP from ALB"
}

resource "aws_security_group_rule" "ecs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Allow all outbound"
}

# ECS Task Definition

resource "aws_ecs_task_definition" "wordpress" {
  family                   = "${var.name_prefix}-wordpress"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = var.ecr_image_url
      essential = true

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      # DB host injected as plain env var; credentials come from Secrets Manager
      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = var.db_host
        },
        {
          name  = "WORDPRESS_DEBUG"
          value = tostring(var.wordpress_debug)
        },
        {
          name  = "WORDPRESS_FORCE_SSL"
          value = tostring(var.wordpress_force_ssl)
        }
      ]

      # Credentials injected from Secrets Manager
      secrets = [
        {
          name      = "WORDPRESS_DB_USER"
          valueFrom = "${var.secret_arn}:username::"
        },
        {
          name      = "WORDPRESS_DB_PASSWORD"
          valueFrom = "${var.secret_arn}:password::"
        },
        {
          name      = "WORDPRESS_DB_NAME"
          valueFrom = "${var.secret_arn}:dbname::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wordpress"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost/wp-login.php || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Allow ECS Exec
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = { Name = "${var.name_prefix}-wordpress-task" }
}

# ECS Service

resource "aws_ecs_service" "wordpress" {
  name                               = "${var.name_prefix}-wordpress"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.wordpress.arn
  desired_count                      = var.ecs_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true  # Allows `aws ecs execute-command` for debugging
  health_check_grace_period_seconds  = 120

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = "wordpress"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    # Prevent Terraform from reverting manual task count changes
    ignore_changes = [desired_count]
  }

  tags = { Name = "${var.name_prefix}-wordpress-service" }

  depends_on = [aws_cloudwatch_log_group.ecs]
}

# Application Auto Scaling

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.wordpress.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale out when average CPU > 70%
resource "aws_appautoscaling_policy" "cpu_scale_out" {
  name               = "${var.name_prefix}-cpu-scale-out"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# Scale out when average memory > 75%
resource "aws_appautoscaling_policy" "memory_scale_out" {
  name               = "${var.name_prefix}-memory-scale-out"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# CloudWatch Alarms

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization is high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.wordpress.name
  }

  tags = { Name = "${var.name_prefix}-ecs-cpu-alarm" }
}
