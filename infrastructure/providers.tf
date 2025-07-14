# Configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# Data source to get the current AWS account ID
data "aws_caller_identity" "current" {}