variable "project_name" {
  description = "A unique name for the project."
  type        = string
}

variable "aws_region" {
  description = "The AWS region."
  type        = string
}

variable "lambda_iam_role_arn" {
  description = "ARN of the IAM role for AWS Lambda functions."
  type        = string
}

variable "bedrock_access_iam_role_arn" {
  description = "ARN of the IAM role for Bedrock access."
  type        = string
}

variable "s3_lambda_code_bucket_id" {
  description = "ID of the S3 bucket for Lambda deployment packages."
  type        = string
}

variable "sagemaker_endpoint_name" {
  description = "Name of the deployed SageMaker endpoint."
  type        = string
}

variable "sns_anomaly_topic_arn" {
  description = "ARN of the SNS topic for anomaly alerts."
  type        = string
}

variable "bedrock_model_id" {
  description = "The ID of the Amazon Bedrock LLM to use for root cause analysis."
  type        = string
}

variable "s3_processed_data_bucket_id" {
  description = "ID of the S3 bucket for processed data (for Lambda to read)."
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