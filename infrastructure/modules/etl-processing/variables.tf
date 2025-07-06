variable "project_name" {
  description = "A unique name for the project."
  type        = string
}

variable "aws_region" {
  description = "The AWS region."
  type        = string
}

variable "s3_raw_logs_bucket_arn" {
  description = "ARN of the S3 bucket for raw logs."
  type        = string
}

variable "s3_processed_data_bucket_arn" {
  description = "ARN of the S3 bucket for processed data."
  type        = string
}

variable "glue_iam_role_arn" {
  description = "ARN of the IAM role for AWS Glue."
  type        = string
}

variable "s3_model_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for ML model artifacts (where Glue scripts are stored)."
  type        = string
}

variable "glue_job_worker_type" {
  description = "The worker type for Glue ETL jobs."
  type        = string
}

variable "glue_job_number_of_workers" {
  description = "The number of workers for Glue ETL jobs."
  type        = number
}

variable "environment_tag" {
  description = "The value for the 'Environment' tag."
  type        = string
}

variable "owner_tag" {
  description = "The value for the 'Owner' tag."
  type        = string
}

variable "s3_raw_logs_bucket_id" {
  description = "ID of the S3 bucket for raw logs."
  type        = string
}

variable "s3_processed_data_bucket_id" {
  description = "ID of the S3 bucket for processed data."
  type        = string
}