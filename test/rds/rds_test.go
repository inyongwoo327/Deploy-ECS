package test

import (
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/aws/aws-sdk-go/service/rds"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRDSModule(t *testing.T) {
	t.Parallel()

	region := "eu-west-1"
	namePrefix := "wp-unit-rds"

	// 1. Create VPC
	vpcOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/vpc",
		Vars: map[string]interface{}{
			"name_prefix":          namePrefix + "-vpc",
			"vpc_cidr":             "10.98.0.0/16",
			"public_subnet_cidrs":  []string{"10.98.1.0/24", "10.98.2.0/24"},
			"private_subnet_cidrs": []string{"10.98.3.0/24", "10.98.4.0/24"},
			"availability_zones":   []string{"eu-west-1a", "eu-west-1b"},
		},
		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})
	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	privateSubnets := terraform.OutputList(t, vpcOpts, "private_subnet_ids")

	// 2. MANUAL Security Group creation using AWS SDK (Avoids Terratest alias issues)
	sess, _ := session.NewSession(&aws.Config{Region: aws.String(region)})
	ec2Client := ec2.New(sess)

	sgOutput, err := ec2Client.CreateSecurityGroup(&ec2.CreateSecurityGroupInput{
		Description: aws.String("Stub SG for RDS test"),
		GroupName:   aws.String(namePrefix + "-stub-sg"),
		VpcId:       aws.String(vpcID),
	})
	require.NoError(t, err)
	ecsSGID := *sgOutput.GroupId

	defer ec2Client.DeleteSecurityGroup(&ec2.DeleteSecurityGroupInput{GroupId: aws.String(ecsSGID)})

	// 3. RDS Module Test
	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/rds",
		Vars: map[string]interface{}{
			"name_prefix":              namePrefix,
			"vpc_id":                   vpcID,
			"subnet_ids":               privateSubnets,
			"db_name":                  "wordpress",
			"db_username":              "wpuser",
			"db_password":              "TestPass123!",
			"db_instance_class":        "db.t3.micro",
			"db_allocated_storage":     20,
			"db_multi_az":              false,
			"db_backup_retention_days": 1,
			"ecs_security_group_id":    ecsSGID,
		},
		EnvVars: map[string]string{"AWS_DEFAULT_REGION": region},
	})

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// 4. Validate RDS Instance
	rdsClient := rds.New(sess)
	dbInstanceIdentifier := namePrefix + "-mysql"

	dbOut, err := rdsClient.DescribeDBInstances(&rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: aws.String(dbInstanceIdentifier),
	})
	require.NoError(t, err)

	assert.Equal(t, "mysql", *dbOut.DBInstances[0].Engine)
	assert.Equal(t, "wordpress", *dbOut.DBInstances[0].DBName)
}
