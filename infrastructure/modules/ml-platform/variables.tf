variable "project_name" {
  description = "A unique name for the project."
  type        = string
}

variable "aws_region" {
  description = "The AWS region."
  type        = string
}

variable "sagemaker_iam_role_arn" {
  description = "ARN of the IAM role for SageMaker."
  type        = string
}

variable "s3_model_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for ML model artifacts."
  type        = string
}

variable "s3_processed_data_bucket_arn" {
  description = "ARN of the S3 bucket for processed data (for training data)."
  type        = string
}

variable "sagemaker_instance_type_training" {
  description = "The instance type for SageMaker training jobs."
  type        = string
}

variable "sagemaker_instance_type_inference" {
  description = "The instance type for SageMaker inference endpoints."
  type        = string
}

variable "sagemaker_model_name" {
  description = "The name for the SageMaker model."
  type        = string
}

variable "sagemaker_endpoint_name" {
  description = "The name for the SageMaker endpoint."
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