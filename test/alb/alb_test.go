// Unit tests for terraform/modules/alb
// Run: go test -v -timeout 15m

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestALBModule(t *testing.T) {
	t.Parallel()

	region := "eu-west-1"
	namePrefix := "wp-unit-alb"

	// VPC for prerequisite resources
	vpcOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/vpc",
		Vars: map[string]interface{}{
			"name_prefix":          namePrefix + "-vpc",
			"vpc_cidr":             "10.97.0.0/16",
			"public_subnet_cidrs":  []string{"10.97.1.0/24", "10.97.2.0/24"},
			"private_subnet_cidrs": []string{"10.97.3.0/24", "10.97.4.0/24"},
			"availability_zones":   []string{"eu-west-1a", "eu-west-1b"},
		},
		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})
	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOpts, "public_subnet_ids")

	// ALB module under test
	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/alb",

		Vars: map[string]interface{}{
			"name_prefix":       namePrefix,
			"vpc_id":            vpcID,
			"public_subnet_ids": publicSubnets,
		},

		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// 1. dns_name is non-empty
	dnsName := terraform.Output(t, opts, "dns_name")
	assert.NotEmpty(t, dnsName, "ALB dns_name should not be empty")

	// 2. DNS name ends with .elb.amazonaws.com
	assert.Contains(t, dnsName, ".elb.amazonaws.com",
		"ALB DNS name should end with .elb.amazonaws.com",
	)

	// 3. zone_id is returned
	assert.NotEmpty(t, terraform.Output(t, opts, "zone_id"),
		"zone_id should not be empty",
	)

	// 4. target_group_arn is a valid ARN
	tgARN := terraform.Output(t, opts, "target_group_arn")
	assert.NotEmpty(t, tgARN)
	assert.Contains(t, tgARN, "arn:aws:elasticloadbalancing:",
		"target_group_arn should be a valid ELB ARN",
	)

	// 5. security_group_id is returned
	assert.NotEmpty(t, terraform.Output(t, opts, "security_group_id"),
		"security_group_id should not be empty",
	)

	// 6. ALB arn is a valid ARN
	albARN := terraform.Output(t, opts, "arn")
	assert.NotEmpty(t, albARN)
	assert.Contains(t, albARN, "arn:aws:elasticloadbalancing:",
		"ALB arn should be a valid ELB ARN",
	)
}
