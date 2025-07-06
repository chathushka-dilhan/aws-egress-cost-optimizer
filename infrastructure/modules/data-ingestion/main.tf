# This Terraform module sets up data ingestion components for AWS egress cost optimization.
# It includes VPC Flow Logs, S3 bucket access logging, and a sample CloudFront distribution
# with access logging to an S3 bucket.

# --- VPC Flow Logs ---
# Enables VPC Flow Logs for specified VPCs, delivering them to an S3 bucket via Kinesis Firehose.

# Kinesis Data Firehose Delivery Stream for VPC Flow Logs
resource "aws_kinesis_firehose_delivery_stream" "vpc_flow_logs_stream" {
  name        = "${var.project_name}-vpc-flow-logs-delivery"
  destination = "s3"

  extended_s3_configuration {
    role_arn           = var.firehose_iam_role_arn
    bucket_arn         = var.s3_raw_logs_bucket_arn
    prefix             = "vpc_flow_logs/"
    buffering_size     = 5
    buffering_interval = 300
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = var.firehose_log_group_name
      log_stream_name = "s3-delivery"
    }
  }

  tags = {
    Name        = "${var.project_name}-vpc-flow-logs-delivery"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Enable VPC Flow Logs for each specified VPC
resource "aws_vpc_flow_log" "vpc_flow_logs" {
  for_each = toset(var.vpc_ids) # Iterate over the list of VPC IDs

  log_destination      = aws_kinesis_firehose_delivery_stream.vpc_flow_logs_stream.arn
  log_destination_type = "KinesisFirehose"
  traffic_type         = "ALL" # Capture all traffic
  vpc_id               = each.key

  tags = {
    Name        = "${var.project_name}-flow-log-${each.key}"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# --- S3 Bucket Access Logging ---
# Enables access logging for the raw logs S3 bucket itself, and potentially other critical S3 buckets.
# This helps track who accesses the raw data.

resource "aws_s3_bucket_logging" "raw_logs_access_logging" {
  bucket        = var.s3_raw_logs_bucket_id # The bucket to enable logging for
  target_bucket = var.s3_raw_logs_bucket_id # Logs go into the same bucket
  target_prefix = "s3_access_logs/" # Prefix for access log objects
}

# --- CloudFront Distribution and Access Logging Integration ---
# This creates a sample CloudFront distribution and configures its access logging
# to send logs to the designated raw logs S3 bucket.
resource "aws_cloudfront_distribution" "example_cloudfront_distribution" {
  origin {
    domain_name = var.cloudfront_origin_domain_name # e.g., an S3 bucket endpoint or EC2 load balancer
    origin_id   = "myS3Origin" # Unique ID for the origin
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for egress cost optimization example"
  default_root_object = var.cloudfront_default_root_object # e.g., "index.html"

  default_cache_behavior {
    allowed_methods        = var.cloudfront_allowed_methods # e.g., ["GET", "HEAD"]
    cached_methods         = var.cloudfront_cached_methods # e.g., ["GET", "HEAD"]
    target_origin_id       = "myS3Origin"

    forwarded_values {
      query_string = false
      headers      = ["Origin"] # Example: Forward Origin header
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = var.cloudfront_viewer_protocol_policy # e.g., "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # Or "whitelist", "blacklist"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # Use default CloudFront certificate
  }

  # Access logging configuration: logs are sent to the raw logs S3 bucket
  logging_config {
    bucket = aws_s3_bucket_logging.raw_logs_access_logging.target_bucket # Use the raw logs bucket ID
    prefix = "cloudfront_access_logs/" # Prefix for CloudFront access log objects
  }

  tags = {
    Name        = "${var.project_name}-cloudfront-distribution"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}