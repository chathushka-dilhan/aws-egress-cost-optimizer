variable "project_name" {
  description = "A unique name for the project."
  type        = string
}

variable "aws_region" {
  description = "The AWS region."
  type        = string
}

variable "vpc_ids" {
  description = "A list of VPC IDs for which to enable VPC Flow Logs."
  type        = list(string)
}

variable "s3_raw_logs_bucket_id" {
  description = "ID of the S3 bucket for raw logs."
  type        = string
}

variable "s3_raw_logs_bucket_arn" {
  description = "ARN of the S3 bucket for raw logs."
  type        = string
}

variable "firehose_iam_role_arn" {
  description = "ARN of the IAM role for Kinesis Data Firehose."
  type        = string
}

variable "firehose_log_group_name" {
  description = "Name of the CloudWatch Log Group for Firehose."
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

# --- CloudFront Specific Variables ---
variable "cloudfront_origin_domain_name" {
  description = "The domain name of the origin (e.g., S3 bucket endpoint, ALB DNS name)."
  type        = string
  # Example: default = "my-website-bucket.s3.amazonaws.com"
}

variable "cloudfront_default_root_object" {
  description = "The default object (e.g., index.html) that CloudFront returns when a viewer requests the root URL."
  type        = string
  default     = "index.html"
}

variable "cloudfront_allowed_methods" {
  description = "List of HTTP methods that CloudFront processes and forwards to your origin."
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cloudfront_cached_methods" {
  description = "List of HTTP methods that CloudFront caches."
  type        = list(string)
  default     = ["GET", "HEAD"]
}

variable "cloudfront_viewer_protocol_policy" {
  description = "The protocol policy for viewers to access the content."
  type        = string
  default     = "redirect-to-https" # Options: "allow-all", "https-only", "redirect-to-https"
}