output "sns_anomaly_topic_arn" {
  description = "ARN of the SNS topic for anomaly alerts."
  value       = aws_sns_topic.anomaly_alerts_topic.arn
}

output "quicksight_data_source_id" {
  description = "ID of the QuickSight data source for egress data."
  value       = aws_quicksight_data_source.egress_data_source.data_source_id
}