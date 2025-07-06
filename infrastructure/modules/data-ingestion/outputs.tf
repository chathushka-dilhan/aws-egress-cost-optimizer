output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream for VPC Flow Logs."
  value       = aws_kinesis_firehose_delivery_stream.vpc_flow_logs_stream.name
}

output "cloudfront_distribution_id" {
  description = "The ID of the example CloudFront distribution."
  value       = aws_cloudfront_distribution.example_cloudfront_distribution.id
}

output "cloudfront_domain_name" {
  description = "The domain name corresponding to the distribution."
  value       = aws_cloudfront_distribution.example_cloudfront_distribution.domain_name
}