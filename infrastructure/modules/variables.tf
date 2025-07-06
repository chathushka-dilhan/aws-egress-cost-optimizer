variable "project_name" {
  description = "A unique name for the project."
  type        = string
}

variable "aws_region" {
  description = "The AWS region."
  type        = string
}

variable "aws_account_id" {
  description = "The AWS account ID."
  type        = string
}

variable "s3_bucket_suffix" {
  description = "A unique suffix for S3 bucket names."
  type        = string
}

variable "environment_tag" {
  description = "The value for the 'Environment' tag."
  type        = string
}

variable "owner_tag" {
  description = "The value for the 'Owner' tag."
  type        = string
}