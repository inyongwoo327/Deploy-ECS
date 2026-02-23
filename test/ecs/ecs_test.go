// Unit tests for terraform/modules/ecs
// Run: go test -v -timeout 25m ecs_test.go

package test

import (
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"

	terraaws "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestECSModule(t *testing.T) {
	t.Parallel()

	// Configuration & Randomization
	region := "eu-west-1"
	uniqueID := random.UniqueId()
	namePrefix := fmt.Sprintf("wp-ecs-%s", uniqueID)
	accountID := terraaws.GetAccountId(t)

	// Stub/Mock ARNs for dependencies
	mockALBSG := "sg-0123456789abcdef0"
	mockTargetGroup := fmt.Sprintf("arn:aws:elasticloadbalancing:%s:%s:targetgroup/%s-tg/123", region, accountID, namePrefix)
	mockSecret := fmt.Sprintf("arn:aws:secretsmanager:%s:%s:secret:wp-db-pw-123", region, accountID)

	// Step 1: Create VPC (Required for ECS Networking)
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

	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	privateSubnets := terraform.OutputList(t, vpcOpts, "private_subnet_ids")

	// Step 2: ECS Module Under Test
	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/ecs",

		Vars: map[string]interface{}{
			"name_prefix":             namePrefix,
			"aws_region":              region,
			"vpc_id":                  vpcID,
			"private_subnet_ids":      privateSubnets,
			"alb_security_group_id":   mockALBSG,
			"alb_target_group_arn":    mockTargetGroup,
			"task_execution_role_arn": fmt.Sprintf("arn:aws:iam::%s:role/ecsTaskExecutionRole", accountID),
			"task_role_arn":           fmt.Sprintf("arn:aws:iam::%s:role/ecsTaskRole", accountID),
			"ecr_image_url":           fmt.Sprintf("%s.dkr.ecr.%s.amazonaws.com/wordpress:latest", accountID, region),
			"secret_arn":              mockSecret,
			"db_host":                 "stub-rds-endpoint.aws.com",
			"ecs_task_cpu":            256,
			"ecs_task_memory":         512,
		},

		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})

	// Clean up after test
	defer terraform.Destroy(t, opts)

	// Run Init and Apply. Using 'E' version to catch errors before assertions.
	_, err := terraform.InitAndApplyE(t, opts)
	require.NoError(t, err, "Terraform apply failed for ECS module")

	// Step 3: Validations

	// (1) Validate Cluster
	clusterName := terraform.Output(t, opts, "cluster_name")
	assert.Equal(t, namePrefix+"-cluster", clusterName)
	assert.Contains(t, terraform.Output(t, opts, "cluster_arn"), clusterName)

	// (2) Validate Service
	serviceName := terraform.Output(t, opts, "service_name")
	assert.NotEmpty(t, serviceName)

	// (3) Validate Task Definition
	taskARN := terraform.Output(t, opts, "task_definition_arn")
	assert.Contains(t, taskARN, "arn:aws:ecs:")

	// (4) Validate Networking (Security Groups)
	taskSG := terraform.Output(t, opts, "task_security_group_id")
	assert.NotEmpty(t, taskSG)
}
