variable "project_name" {
  description = "A unique name for the project."
  type        = string
}

variable "aws_region" {
  description = "The AWS region."
  type        = string
}

variable "notification_email" {
  description = "Email address to subscribe to SNS anomaly alerts."
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

variable "high_egress_cost_threshold" {
  description = "The threshold for the CloudWatch alarm on daily egress cost (in USD)."
  type        = number
  default     = 100.0 # Default to $100, customize as needed
}

variable "aws_account_id" {
  description = "The AWS account ID."
  type        = string
}

variable "quicksight_iam_role_arn" {
  description = "ARN of the IAM role for QuickSight to access data."
  type        = string
}