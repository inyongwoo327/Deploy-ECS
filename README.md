# WordPress on AWS ECS — DevOps Test

> Terraform · Packer · Ansible · Docker · RDS · ECS

---

## Table of Contents

1. [How did you approach the test?](#1-How did you approach the test?)
2. [What components interact with each other?](#2-What components interact with each other?)
3. [How did you run your project?](#3-How did you run your project?)
4. [What problems did you encounter?](#4-What problems did you encounter?)
5. [How would you have done things to achieve the best HA/automated architecture?](#5-How would you have done things to achieve the best HA/automated architecture?)
6. [Can you share any ideas you have to improve this kind of infrastructure?](#6-Can you share any ideas you have to improve this kind of infrastructure?)
7. [What would be your advice and choices to achieve putting the project to production?](#7-What would be your advice and choices to achieve putting the project to production?)

---

## 1. How did you approach the test?

The goal is to deploy a WordPress container on ECS backed by an RDS MySQL database, using the following toolchain:

- **Packer and Ansible** → build a custom Docker image with WordPress pre-configured
- **Terraform** → provision all AWS infrastructure (VPC, ECS, RDS, ALB, IAM, etc.)
- **Docker** → container runtime for the WordPress image
- **ECR** → AWS based registry to host the custom image

My approach is to keep a clean separation of concerns:

1. **Image layer** — Packer calls Ansible to install and configure WordPress into a Docker image, then pushes it to ECR.
2. **Infrastructure layer** — Terraform provisions the AWS resources that will consume that image.
3. **Runtime layer** — ECS pulls the image from ECR and runs it, reading RDS credentials from AWS Secrets Manager via environment variables.

I started by designing the architecture on paper, then worked outside-in: VPC first, then RDS, then ECS/ALB, and finally the Packer/Ansible pipeline.

---

## 2. What components interact with each other?

**Packer** uses the Docker builder to spin up a container, then delegates all provisioning to the **Ansible** playbook. Ansible downloads WordPress, configures Apache, and sets correct file permissions. Packer commits the resulting container as a new Docker image and pushes it to **ECR**.

**Terraform** provisions all AWS infrastructure. The `vpc` module creates public and private subnets across two availability zones. The `rds` module creates a MySQL `db.t3.micro` instance in the private subnet group with a security group that only accepts traffic from the ECS tasks. The `secrets` module stores the RDS credentials in AWS Secrets Manager. The `ecr` module creates the container registry. The `iam` module creates an ECS task execution role (permission to pull from ECR and read secrets) and a task role (for the running container). The `alb` module creates an internet-facing Application Load Balancer in the public subnets. The `ecs` module creates the Fargate cluster, task definition (referencing the ECR image and Secrets Manager ARNs), and ECS service connected to the ALB target group.

At runtime, ECS Fargate pulls the WordPress image from ECR, injects the RDS credentials as environment variables from Secrets Manager, and the running container connects outbound to RDS. All container logs are shipped to CloudWatch Logs.

---

## 3. How did you run your project?

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.6
- Packer >= 1.10
- Ansible >= 2.15
- Docker (local daemon)
- `jq`

### Step 1 — Bootstrap ECR (one-time)

```bash
cd terraform/
terraform init
terraform apply -target=module.ecr -auto-approve
```

### Step 2 — Build and Push the WordPress Image

```bash
# Authenticate Docker to ECR
# $(aws sts get-caller-identity --query ACCOUNT --output text) returns AWS Account Number
aws ecr get-login-password --region eu-west-1 \
  | docker login --username USERNAME --password-stdin \
    $(aws sts get-caller-identity --query ACCOUNT --output text).dkr.ecr.eu-west-1.amazonaws.com

# Build image with Packer
cd ../packer/
packer init .
packer build wordpress.pkr.hcl
```

### Step 3 — Deploy All Infrastructure

```bash
cd ../terraform/
terraform apply
```

The ALB DNS name is printed in the outputs. Open it in your browser to complete the WordPress installation wizard.

### Clean Up

```bash
terraform destroy
```

---

## 4. What problems did you encounter?

---

## 5. How would you have done things to achieve the best HA/automated architecture?

To achieve proper high availability and full automation, these are the changes I would make:

**ECS Service Auto Scaling** — attach Application Auto Scaling to the ECS service using CPU and memory alarms in CloudWatch. Define a minimum of 2 tasks (spread across AZs) and a maximum of N based on load.

**RDS Multi-AZ** — a single `multi_az = true` in Terraform gives automatic failover to a standby replica in a second AZ with no application changes needed.

**Aurora Serverless v2** — replace RDS MySQL with Aurora Serverless v2 for ACU-based scaling that matches the web tier elasticity, while staying cost-efficient at low traffic.

**CloudFront in front of ALB** — cache static assets and WordPress pages at edge locations, add AWS WAF rules to block common WordPress attack patterns.

**Blue/Green deployments via CodeDeploy** — ECS supports CodeDeploy blue/green out of the box. New image → new task set → traffic shifted gradually → old task set torn down. Zero-downtime deploys with instant rollback.

**CI/CD pipeline** — GitHub Actions or AWS CodePipeline: on push to `main`, lint Terraform with `tflint`, build image with Packer, push to ECR, trigger ECS service update.

**Secrets rotation** — enable automatic secret rotation in Secrets Manager for the RDS password. The Secrets Manager → RDS integration handles rotation without any downtime.

---

## 6. Can you share any ideas you have to improve this kind of infrastructure?

- **Terraform remote state** — store `terraform.tfstate` in an S3 bucket with DynamoDB locking rather than locally.
- **Terraform workspaces or Terragrunt** — manage `dev`, `staging`, and `prod` environments without duplicating code.
- **Image scanning** — enable ECR image scanning on push and block deployments if critical CVEs are found.
- **Cost tagging** — tag all resources with `Environment`, `Project`, and `Owner` for cost attribution.
- **VPC Flow Logs + GuardDuty** — baseline security monitoring at minimal cost.
- **WordPress caching** — install WP Super Cache or W3 Total Cache via Ansible; add an ElastiCache Redis cluster for object caching.
- **HTTPS everywhere** — provision an ACM certificate via Terraform, attach it to the ALB HTTPS listener, and redirect HTTP → HTTPS with an ALB listener rule.
- **Parameter Store for non-secret config** — keep non-sensitive WordPress settings (site URL, debug flags) in SSM Parameter Store and inject them at task start.

---

## 7. What would be your advice and choices to achieve putting the project to production?

If we want to put the project in production, here are the priorities and choices:

**Security first**

- Enable HTTPS on the ALB with an ACM certificate. Never serve WordPress over plain HTTP in production.
- Restrict the RDS security group to ECS task security group only — no public access.
- Enable AWS WAF on the ALB with the AWS managed WordPress rule group.
- Rotate the RDS password via Secrets Manager before go-live.

**Reliability**

- Set `min_capacity = 2` on the ECS service to ensure at least one task survives an AZ failure.
- Enable RDS Multi-AZ.

**Observability**

- **CloudWatch Container Insights** — enable on the ECS cluster for task-level CPU/memory metrics.
- **CloudWatch Alarms** — alert on ALB 5xx error rate, ECS CPU > 80%, RDS connection count, and RDS free storage.
- **Datadog or Grafana Cloud (free tier)** — richer dashboards and APM if budget allows.
- **Uptime monitoring** — UptimeRobot (free) or Pingdom for external availability checks.
- **WordPress application logging** — configure WordPress to write errors to `php://stderr` so they flow into CloudWatch Logs.

**Backups**

- Enable automated RDS snapshots (7-day retention minimum).
- Test restore procedures before going live.

**DNS and CDN**

- Point a real domain via Route 53 to the ALB.
- Put CloudFront in front of the ALB for caching and DDoS protection from day one.

**Things I would improve given more time**

- Replace the WordPress install wizard with an Ansible task that pre-seeds the `wp_options` table, so the site is fully configured without manual steps after `terraform apply`.
- Add a `wp-cli` step in the Ansible playbook to install and activate a theme and required plugins automatically.
- Write Terratest integration tests to validate the ALB health check returns 200 after a full `terraform apply`.
- Build out a full GitOps pipeline where merging to `main` triggers image build, infrastructure plan, and — after manual approval — deployment.