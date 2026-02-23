// Unit tests for terraform/modules/vpc
// Run: go test -v -timeout 15m

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVPCModule(t *testing.T) {
	t.Parallel()

	region := "eu-west-1"
	namePrefix := "wp-unit-vpc"

	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/vpc",

		Vars: map[string]interface{}{
			"name_prefix":          namePrefix,
			"vpc_cidr":             "10.99.0.0/16",
			"public_subnet_cidrs":  []string{"10.99.1.0/24", "10.99.2.0/24"},
			"private_subnet_cidrs": []string{"10.99.3.0/24", "10.99.4.0/24"},
			"availability_zones":   []string{"eu-west-1a", "eu-west-1b"},
		},

		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
	})

	// Always clean up — even on test failure
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// 1. VPC ID is non-empty
	vpcID := terraform.Output(t, opts, "vpc_id")
	assert.NotEmpty(t, vpcID, "vpc_id output should not be empty")

	// 2. VPC exists in AWS with the correct CIDR
	vpc := aws.GetVpcById(t, vpcID, region)
	require.NotNil(t, vpc, "VPC should exist in AWS")
	assert.Equal(t, "10.99.0.0/16", *vpc.CidrBlock, "VPC CIDR should match the variable")

	// 3. VPC CIDR block output matches
	assert.Equal(t, "10.99.0.0/16",
		terraform.Output(t, opts, "vpc_cidr_block"),
	)

	// 4. Exactly 2 public subnets
	publicIDs := terraform.OutputList(t, opts, "public_subnet_ids")
	assert.Len(t, publicIDs, 2, "should have exactly 2 public subnets")

	// 5. Exactly 2 private subnets
	privateIDs := terraform.OutputList(t, opts, "private_subnet_ids")
	assert.Len(t, privateIDs, 2, "should have exactly 2 private subnets")

	// 6. Public and private subnet ID lists are different
	assert.NotEqual(t, publicIDs, privateIDs,
		"public and private subnet IDs should be different",
	)
}
