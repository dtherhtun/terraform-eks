package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestTerraformEKS(t *testing.T) {
	t.Parallel()

	const (
		awsRegion           = "us-east-1"
		expectedClusterName = "opslab-eks"
		expectedVpc         = "opslab-vpc"
	)
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../",
		//		Vars: map[string]interface{}{
		//			"cluster_name": expectedClusterName,
		//			"region":       awsRegion,
		//		},
	})
	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	publicSubnetID := terraform.Output(t, terraformOptions, "public_subnets")
	privateSubnetID := terraform.Output(t, terraformOptions, "private_subnets")
	outputClusterName := terraform.Output(t, terraformOptions, "cluster_id")

	assert.Equal(t, expectedClusterName, outputClusterName)
	assert.True(t, aws.IsPublicSubnet(t, publicSubnetID, awsRegion))
	assert.False(t, aws.IsPublicSubnet(t, privateSubnetID, awsRegion))
}
