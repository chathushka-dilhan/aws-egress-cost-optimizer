# Specify the required Terraform version
terraform {
  required_version = ">= 1.0.0" # Ensure compatibility with modern Terraform features

  # Configure the S3 backend for Terraform state management
  # This is crucial for collaborative development and state persistence.
  # IMPORTANT: You'll need to create this S3 bucket and DynamoDB table manually ONCE
  # before running `terraform init` for the first time.
  backend "s3" {
    bucket         = "tfstate-egress-cost-optimizer-YOUR_ACCOUNT_ID" # IMPORTANT: Customize this bucket name!
    key            = "terraform.tfstate"
    region         = "us-east-1" # IMPORTANT: Use a dedicated region for your tfstate bucket
    dynamodb_table = "tfstate-egress-cost-optimizer-locks" # IMPORTANT: Customize this table name!
    encrypt        = true
  }

  # Specify the required provider versions
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}