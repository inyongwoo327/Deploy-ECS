# WordPress Deploy on AWS ECS

> Terraform · Packer · Ansible · Docker · RDS · ECS

---

## Table of Contents

1. How did you approach the test?
2. What components interact with each other?
3. How did you run your project?
4. What problems did you encounter?
5. How would you have done things to achieve the best HA/automated architecture?
6. Can you share any ideas you have to improve this kind of infrastructure?
7. What would be your advice and choices to achieve putting the project to production?

---

## 1. How did you approach the test?

The goal is to deploy a WordPress container on ECS backed by an RDS MySQL database, using the following toolchain:

- **Packer and Ansible** → build a custom Docker image with WordPress pre-configured
- **Terraform** → provision all AWS infrastructure (VPC, ECS, RDS, ALB, IAM, etc.)
- **Docker** → container runtime for the WordPress image
- **ECR** → AWS based registry to host the custom image

My approach is to keep a clean separation of concerns:

1. **Image layer** — Packer calls Ansible to install and configure WordPress into a Docker image, then pushes it to ECR.
2. **Infrastructure layer** — Terraform provisions the AWS resources that will use that image.
3. **Runtime layer** — ECS pulls the image from ECR and runs it, reading RDS credentials from AWS Secrets Manager via environment variables.

Started by designing terraform modules and the Packer/Ansible pipeline. Wrote down the vpc, ECR, Secrets, RDS, IAM, ALB, ECS modules with terratest based unit tests and so on. Furthermore, wrote down terraform root main.tf with variables, Ansible role variables, tasks, templates (with Jinja2), and playbook files.

---

## 2. What components interact with each other?

**Packer** uses the Docker builder to spin up a container, then delegates all provisioning to the **Ansible** playbook. Ansible downloads WordPress, configures Apache, and sets correct file permissions. Packer commits the resulting container as a new Docker image during packer build process then pushes it to **ECR**.

**Terraform** provisions AWS infrastructure resources. The `vpc` module creates public and private subnets across two availability zones. The `rds` module creates a MySQL `db.t3.micro` instance in the private subnet group with a security group that only accepts traffic from the ECS tasks. The `secrets` module stores the RDS credentials in AWS Secrets Manager. The `ecr` module creates the container registry. The `iam` module creates an ECS task execution role (permission to pull from ECR and read secrets) and a task role (for the running container). The `alb` module creates an internet-facing Application Load Balancer in the public subnets. The `ecs` module creates the Fargate cluster, task definition (Image created by packer build and saved in ECR), and ECS service connected to the ALB target group.

At runtime, ECS pulls the WordPress image from ECR, injects the RDS credentials as environment variables from Secrets Manager, and the running container connects outbound to RDS. All container logs are shipped to CloudWatch Logs.

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

### Step 2 — Create ECR then build and Push the WordPress Image to ECR

```bash
# Make surev that AWS credentials are set
aws configure

cd Deploy-ECS/terraform
Terraform plan
cd ..
cd packer
packer init packer/wordpress.pkr.hcl
cd ansible
ansible-galaxy collection install -r packer/ansible/requirements.yml
ansible-galaxy collection install community.docker --upgrade
cd ..
packer validate -var "aws_account_id=$(aws sts get-caller-identity --query Account --output text)" wordpress.pkr.hcl
packer build -var "aws_account_id=$(aws sts get-caller-identity --query Account --output text)" wordpress.pkr.hcl
```
### Step 3 — Deploy All Infrastructure

```bash
cd ../terraform/
terraform apply
```

### Step 4 - Clean Up

```bash
terraform destroy
```

---

## 4. What problems did you encounter?
During the development and deployment of this infrastructure, faced and solved the following technical challenges that required deep-dives into architecture compatibility, credential management, and so on:

### 1. Circular Dependencies and Empty Secret Variables:
Initially, the Secrets Manager module was creating the database credential JSON with an empty host string. This caused the WordPress container to fail its database handshake because the actual RDS endpoint wasn't available at the time the secret was first initialized.

Resolution: Refactored the module "wiring" to pass the address output from the RDS module into the db_host variable of the Secrets module. By referencing module.rds.address in the root main.tf, created a clear dependency graph that ensured the RDS instance was provisioned and its endpoint known before the secret version was finalized.

### 2. Secrets Manager Recovery Window Conflict:
When redeploying the stack after a failure or manual destruction, Terraform was unable to recreate the database credentials secret. This was because AWS Secrets Manager defaults to a 7-to-30 day recovery window where a deleted secret name cannot be reused.

Resolution: Modified the aws_secretsmanager_secret resource to include a random_id suffix in the name (db-credentials-${random_id.secret_suffix.hex}). This ensured every deployment generated a unique secret name, bypassing the conflict. Also set recovery_window_in_days = 0 to facilitate easier cleanup in development.

### 3. CPU Architecture Mismatch (Exec Format Error):
The most significant hurdle was an Exec format error captured in the ECS Task logs. This occurred because the Docker image was built on a local Mac (ARM64 architecture) using Packer , while the AWS ECS cluster was defaulting to X86_64.

Resolution: Synchronized the architecture, updated the Packer run_command to explicitly use --platform linux/arm64 and revised the ECS aws_ecs_task_definition to include the runtime_platform block specifying ARM64.

### 4. Apache Configuration Issue:
ServerTokens is a global Apache directive. It can't go inside a <VirtualHost> block. 

Resolution: Moved ServerTokens and ServerSignature outside the VirtualHost block.

### 5. AWS Service Limits:
Early in the testing phase, automated deployments failed due to AWS account-level restrictions on creating Application Load Balancers.

Resolution: Reached out to AWS Support Team directly then asked them to remove the restrictions on an account of creating Load Balancers (Ex. alb). Eventually, AWS support team responded promptly and removed the restrictions. 

## 5. How would you have done things to achieve the best HA/automated architecture?

The current project runs a single ECS task against a single-AZ RDS instance, which is not ideal in Production. 
To achieve proper high availability and full automation, these are the suggestions to consider:

**Multiple NAT Gateways** - a single NAT gateway is itself a single point of failure, so add a NAT Gateway per availability zone.  

**ECS Service Auto Scaling** — attach Application Auto Scaling to the ECS service using CPU and memory alarms in CloudWatch. Define a minimum of 2 tasks (spread across AZs) and a maximum of N based on load.

**RDS Multi-AZ** — a single `multi_az = true` in Terraform gives automatic failover to a standby replica in a second AZ with no application changes needed.

**Aurora Serverless v2** — replace RDS MySQL with Aurora Serverless v2 for ACU-based scaling that matches the web tier elasticity, while staying cost-efficient at low traffic.

**CloudFront in front of ALB** — cache static assets and WordPress pages at edge locations, add AWS WAF rules to block common WordPress attack patterns.

**CI/CD pipeline** — GitHub Actions or AWS CodePipeline: on push to `main`, lint Terraform with `tflint`, build image with Packer, push to ECR, trigger ECS service update.

---

## 6. Can you share any ideas you have to improve this kind of infrastructure?

- **Terraform workspaces or Terragrunt** — manage `dev`, `staging`, and `prod` environments without duplicating code.
- **HTTPS in Load Balancing** - use Terraform to provision and add HTTPS to the ALB with an ACM certificate
- **Cost tagging** — tag all resources with `Environment`, `Project`, and `Owner` for cost attribution.
- **VPC Flow Logs + GuardDuty** — ship VPC Flow Logs to CloudWatch and enable GuardDuty.
- **Parameter Store for non-secret config** — keep non-sensitive WordPress settings (Ex. site URL) in SSM Parameter Store and inject them at task start.

---

## 7. What would be your advice and choices to achieve putting the project to production?

When releasing the project to production, here are the priorities and choices:

**Security first**

- Enable HTTPS on the ALB with an ACM certificate. Never serve WordPress over plain HTTP in production.
- Restrict the RDS security group to ECS task security group only, so it will not allow public access.
- Rotate the RDS password via Secrets Manager before go-live.

**Reliability**

- Set `min_capacity = 2` on the ECS service to ensure at least one task survives an AZ failure.
- Enable RDS Multi-AZ.

**Observability**

- **CloudWatch Container Insights** — enable on the ECS cluster for task-level CPU/memory metrics.
- **CloudWatch Alarms** — alert on ALB 5xx error rate, ECS CPU > 80%, RDS connection count, and RDS free storage.
- **Uptime monitoring** — add external uptime monitor such as UptimeRobot.
- **PagerDuty** — automate and trigger immediate incidents and on-call notification with PagerDuty and CloudWatch Alarms

**Backups**

- Enable automated RDS snapshots (7-day retention minimum).
- Test restore procedures before going live.

**DNS and CDN**

- Point a real domain via Route 53 to the ALB.
- Put CloudFront in front of the ALB for caching and DDoS protection from day one.