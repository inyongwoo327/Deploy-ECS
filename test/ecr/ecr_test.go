// Unit tests for terraform/modules/ecr
// go test -v -timeout 10m

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestECRModule(t *testing.T) {
	t.Parallel()

	region := "eu-west-1"
	namePrefix := "wp-unit-ecr"
	// Dynamically fetch account ID for the policy
	accountID := aws.GetAccountId(t)

	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Points to terraform/modules/ecr
		TerraformDir: "../../terraform/modules/ecr",

		Vars: map[string]interface{}{
			"name_prefix": namePrefix,
			"account_id":  accountID,
		},

		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
	})

	// Clean up after test
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// 1. Validate Repository URL
	repoURL := terraform.Output(t, opts, "repository_url")
	assert.NotEmpty(t, repoURL)
	assert.Contains(t, repoURL, namePrefix)
	assert.Contains(t, repoURL, region)

	// 2. Validate Repository Name
	repoName := terraform.Output(t, opts, "repository_name")
	assert.Equal(t, namePrefix, repoName)

	// 3. Validate ARN Format
	repoARN := terraform.Output(t, opts, "repository_arn")
	assert.Contains(t, repoARN, "arn:aws:ecr:")
}
