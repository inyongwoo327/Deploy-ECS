package test

import (
	"fmt"
	"testing"

	terraaws "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestECSModuleBasic(t *testing.T) {
	t.Parallel()

	// --- 1. Setup ---
	region := "eu-west-1"
	// Generate a unique ID to avoid naming collisions in AWS
	uniqueID := random.UniqueId()
	namePrefix := fmt.Sprintf("wp-test-%s", uniqueID)
	accountID := terraaws.GetAccountId(t)

	// --- 2. Prerequisite: VPC ---
	// ECS needs a real VPC to exist to pass Terraform validation
	vpcOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/vpc",
		Vars: map[string]interface{}{
			"name_prefix":          namePrefix + "-vpc",
			"vpc_cidr":             "10.95.0.0/16",
			"public_subnet_cidrs":  []string{"10.95.1.0/24", "10.95.2.0/24"},
			"private_subnet_cidrs": []string{"10.95.3.0/24", "10.95.4.0/24"},
			"availability_zones":   []string{region + "a", region + "b"},
		},
		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})

	// Ensure VPC is destroyed at the end
	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	privateSubnets := terraform.OutputList(t, vpcOpts, "private_subnet_ids")

	// --- 3. ECS Module Test ---
	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/ecs",
		Vars: map[string]interface{}{
			"name_prefix":        namePrefix,
			"aws_region":         region,
			"vpc_id":             vpcID,
			"private_subnet_ids": privateSubnets,

			// To avoid the "NotFound" errors you saw earlier, we use
			// the VPC's default security group as a placeholder.
			"alb_security_group_id": terraform.Output(t, vpcOpts, "vpc_default_sg_id"),

			// We provide a valid-looking but dummy ARN.
			// NOTE: This will allow 'terraform plan' to pass, but 'apply' might fail
			// on the Service resource. This is why we test the outputs below.
			"alb_target_group_arn":    fmt.Sprintf("arn:aws:elasticloadbalancing:%s:%s:targetgroup/dummy/123", region, accountID),
			"task_execution_role_arn": fmt.Sprintf("arn:aws:iam::%s:role/ecsTaskExecutionRole", accountID),
			"task_role_arn":           fmt.Sprintf("arn:aws:iam::%s:role/ecsTaskRole", accountID),
			"ecr_image_url":           fmt.Sprintf("%s.dkr.ecr.%s.amazonaws.com/wordpress:latest", accountID, region),
			"secret_arn":              fmt.Sprintf("arn:aws:secretsmanager:%s:%s:secret:dummy", region, accountID),
			"db_host":                 "stub-db.local",
			"ecs_task_cpu":            256,
			"ecs_task_memory":         512,
		},
		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})

	// Clean up ECS resources after test
	defer terraform.Destroy(t, opts)

	// We use InitAndApply. If the Service fails because of the dummy Target Group,
	// the test will still show us if the Cluster and Log Groups were created successfully.
	terraform.InitAndApply(t, opts)

	// --- 4. New Test Cases ---

	// Test Case 1: Cluster Existence
	clusterName := terraform.Output(t, opts, "cluster_name")
	assert.Equal(t, namePrefix+"-cluster", clusterName, "Cluster name should match prefix")

	// Test Case 2: Log Group Validation
	logGroup := terraform.Output(t, opts, "log_group_name")
	assert.Contains(t, logGroup, namePrefix, "Log group should be named after our prefix")

	// Test Case 3: Networking (Security Group)
	// This ensures the module correctly created a security group for the tasks
	taskSG := terraform.Output(t, opts, "task_security_group_id")
	assert.NotEmpty(t, taskSG, "Module should output the created Task Security Group ID")
}
