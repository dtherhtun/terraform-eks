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
		awsRegion             = "us-east-1"
		expectedClusterName   = "opslab-eks"
		expectedVpc           = "opslab-vpc"
		expectedCPV           = "eks.5"
		expectedClusterStatus = "ACTIVE"
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

	publicSubnetIDs := terraform.OutputList(t, terraformOptions, "public_subnets")
	publicSubnetID := publicSubnetIDs[0]
	privateSubnetIDs := terraform.OutputList(t, terraformOptions, "private_subnets")
	privateSubnetID := privateSubnetIDs[0]
	outputClusterName := terraform.Output(t, terraformOptions, "cluster_id")
	outputCPV := terraform.Output(t, terraformOptions, "cluster_platform_version")
	outputClusterStatus := terraform.Output(t, terraformOptions, "cluster_status")

	assert.Equal(t, expectedCPV, outputCPV)
	assert.Equal(t, expectedClusterStatus, outputClusterStatus)
	assert.Equal(t, expectedClusterName, outputClusterName)
	assert.True(t, aws.IsPublicSubnet(t, publicSubnetID, awsRegion))
	assert.False(t, aws.IsPublicSubnet(t, privateSubnetID, awsRegion))
}
