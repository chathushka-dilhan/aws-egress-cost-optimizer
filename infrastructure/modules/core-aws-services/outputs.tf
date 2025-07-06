# S3 Bucket IDs
output "s3_raw_logs_bucket_id" {
  description = "ID of the S3 bucket for raw logs."
  value       = aws_s3_bucket.raw_logs.id
}

output "s3_raw_logs_bucket_arn" {
  description = "ARN of the S3 bucket for raw logs."
  value       = aws_s3_bucket.raw_logs.arn
}

output "s3_processed_data_bucket_id" {
  description = "ID of the S3 bucket for processed data."
  value       = aws_s3_bucket.processed_data.id
}

output "s3_processed_data_bucket_arn" {
  description = "ARN of the S3 bucket for processed data."
  value       = aws_s3_bucket.processed_data.arn
}

output "s3_model_artifacts_bucket_id" {
  description = "ID of the S3 bucket for ML model artifacts."
  value       = aws_s3_bucket.model_artifacts.id
}

output "s3_model_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for ML model artifacts."
  value       = aws_s3_bucket.model_artifacts.arn
}

output "s3_lambda_code_bucket_id" {
  description = "ID of the S3 bucket for Lambda deployment packages."
  value       = aws_s3_bucket.lambda_code.id
}

output "s3_lambda_code_bucket_arn" {
  description = "ARN of the S3 bucket for Lambda deployment packages."
  value       = aws_s3_bucket.lambda_code.arn
}

# IAM Role ARNs
output "firehose_iam_role_arn" {
  description = "ARN of the IAM role for Kinesis Data Firehose."
  value       = aws_iam_role.firehose_role.arn
}

output "glue_iam_role_arn" {
  description = "ARN of the IAM role for AWS Glue."
  value       = aws_iam_role.glue_role.arn
}

output "sagemaker_iam_role_arn" {
  description = "ARN of the IAM role for Amazon SageMaker."
  value       = aws_iam_role.sagemaker_role.arn
}

output "lambda_iam_role_arn" {
  description = "ARN of the IAM role for AWS Lambda functions."
  value       = aws_iam_role.lambda_role.arn
}

output "bedrock_access_iam_role_arn" {
  description = "ARN of the IAM role for Bedrock access."
  value       = aws_iam_role.bedrock_access_role.arn
}

output "quicksight_iam_role_arn" {
  description = "ARN of the IAM role for QuickSight."
  value       = aws_iam_role.quicksight_role.arn
}

# CloudWatch Log Group Names
output "firehose_log_group_name" {
  description = "Name of the CloudWatch Log Group for Firehose."
  value       = aws_cloudwatch_log_group.firehose_log_group.name
}

output "sagemaker_log_group_name" {
  description = "Name of the CloudWatch Log Group for SageMaker."
  value       = aws_cloudwatch_log_group.sagemaker_log_group.name
}

output "glue_log_group_name" {
  description = "Name of the CloudWatch Log Group for Glue."
  value       = aws_cloudwatch_log_group.glue_log_group.name
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda."
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}
