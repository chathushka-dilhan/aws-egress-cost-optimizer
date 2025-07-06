# This module sets up monitoring and alerting for egress costs using AWS services.
# It includes:
#   - Amazon SNS for alert notifications
#   - CloudWatch Alarms for cost thresholds
#   - Amazon QuickSight for data visualization

# --- Amazon SNS Topic for Anomaly Alerts ---
# This topic will receive messages when egress cost anomalies are detected.
resource "aws_sns_topic" "anomaly_alerts_topic" {
  name = "${var.project_name}-anomaly-alerts"

  tags = {
    Name        = "${var.project_name}-anomaly-alerts"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# SNS Topic Subscription (e.g., Email)
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.anomaly_alerts_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- CloudWatch Alarms for high-level cost monitoring ---
# This alarm will notify when daily egress cost exceeds a specified threshold.
# This provides a high-level safety net even before ML model detects subtle anomalies.
# IMPORTANT: Ensure AWS Cost Explorer daily granularity is enabled in your AWS account.
resource "aws_cloudwatch_metric_alarm" "high_egress_cost_alarm" {
  alarm_name          = "${var.project_name}-high-egress-cost-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlendedCost" # This metric represents your total incurred cost
  namespace           = "AWS/Billing"
  period              = 86400 # Daily (in seconds)
  statistic           = "Sum"
  threshold           = var.high_egress_cost_threshold # Set threshold (e.g., $100 daily egress)
  alarm_description   = "Alarm when daily egress cost exceeds threshold."
  alarm_actions       = [aws_sns_topic.anomaly_alerts_topic.arn]
  ok_actions          = [aws_sns_topic.anomaly_alerts_topic.arn]

  # Dimensions to filter by service for egress.
  # "DataTransfer-Out-Bytes" is a common UsageType for egress.
  # You might need to adjust dimensions based on how your CUR reports categorize egress.
  dimensions = {
    Service   = "Amazon Elastic Compute Cloud" # Example: Filter by EC2 egress
    UsageType = "DataTransfer-Out-Bytes" # Refine for specific egress types
  }
  # For more detailed egress monitoring, consider creating custom metrics from your processed data
  # in Log Analytics or S3 and setting alarms on those.
}

# --- Amazon QuickSight Data Source for Dashboards ---
# This resource configures a QuickSight data source that connects to Athena/Glue Data Catalog.
# You would manually connect QuickSight to your Glue Data Catalog tables (backed by S3 processed data)
# to build interactive dashboards for egress cost visualization.
resource "aws_quicksight_data_source" "egress_data_source" {
  data_source_id = "${var.project_name}-egress-data-source" # Unique ID for the data source
  name           = "${var.project_name}-egress-data-source"
  type           = "ATHENA"
  aws_account_id = var.aws_account_id # Pass the AWS account ID from the root module

  parameters {
    athena {
      work_group = "primary" # Or a dedicated Athena workgroup (e.g., created in etl-processing module)
    }
  }

  # Permissions for QuickSight to assume the role and access data
  permission {
    principal  = var.quicksight_iam_role_arn # Role QuickSight assumes, defined in core-aws-services
    actions    = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:ListDataSets",
      "quicksight:ListDataSetRefreshStatuses",
      "quicksight:UpdateDataSetPermissions",
      "quicksight:CreateDataSet", # Added for creating datasets from this data source
      "quicksight:DeleteDataSet"
    ]
  }

  tags = {
    Name        = "${var.project_name}-egress-data-source"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}