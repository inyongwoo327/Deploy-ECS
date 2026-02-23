// Unit tests for terraform/modules/ecr
// go test -v -timeout 10m

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
)

func TestECRModule(t *testing.T) {
	t.Parallel()

	region := "eu-west-1"
	namePrefix := "wp-unit-ecr"

	accountID := aws.GetAccountId(t)

}
