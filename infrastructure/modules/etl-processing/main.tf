# This Terraform module sets up ETL processing components for AWS egress cost optimization.
# It includes AWS Glue Data Catalog databases, crawlers, and jobs to process VPC Flow Logs and AWS Cost and Usage Reports (CUR).
# The processed data can be queried using Amazon Athena or used for further analysis.

# --- AWS Glue Data Catalog ---
# Defines databases and tables for the raw and processed data.

# Glue Database for raw logs (VPC Flow Logs, CUR, S3 Access Logs, CloudFront Logs)
resource "aws_glue_catalog_database" "raw_logs_db" {
  name = "${var.project_name}_raw_logs_db"

  tags = {
    Name        = "${var.project_name}-raw-logs-db"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Glue Database for processed data
resource "aws_glue_catalog_database" "processed_data_db" {
  name = "${var.project_name}_processed_data_db"

  tags = {
    Name        = "${var.project_name}-processed-data-db"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# --- AWS Glue Crawlers ---
# Crawlers automatically discover schema from data in S3 and populate the Data Catalog.

# Crawler for VPC Flow Logs
resource "aws_glue_crawler" "vpc_flow_logs_crawler" {
  database_name = aws_glue_catalog_database.raw_logs_db.name
  name          = "${var.project_name}-vpc-flow-logs-crawler"
  role          = var.glue_iam_role_arn
  schedule      = "cron(0 0 * * ? *)" # Run daily at midnight UTC

  s3_target {
    path = "${var.s3_raw_logs_bucket_arn}/vpc_flow_logs/"
  }

  tags = {
    Name        = "${var.project_name}-vpc-flow-logs-crawler"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Crawler for AWS Cost and Usage Reports (CUR)
# IMPORTANT: Ensure CUR is enabled in your Billing console and delivered to the raw_logs S3 bucket.
resource "aws_glue_crawler" "cur_crawler" {
  database_name = aws_glue_catalog_database.raw_logs_db.name
  name          = "${var.project_name}-cur-crawler"
  role          = var.glue_iam_role_arn
  schedule      = "cron(0 0 * * ? *)" # Run daily at midnight UTC

  s3_target {
    # Adjust this path to where your CUR reports are delivered in the S3 bucket
    path = "${var.s3_raw_logs_bucket_arn}/CUR/REPORT/" # Customize CUR path!
  }

  tags = {
    Name        = "${var.project_name}-cur-crawler"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# --- AWS Glue Jobs ---
# Defines ETL jobs that process data. The actual script content is external (data_processing_scripts/).

# Glue Job for parsing CUR and aggregating egress costs
resource "aws_glue_job" "cur_parser_job" {
  name            = "${var.project_name}-cur-parser-job"
  role_arn        = var.glue_iam_role_arn
  command {
    script_location = "${var.s3_model_artifacts_bucket_arn}/glue_scripts/cur_parser.py" # Script location in S3
    python_version  = "3"
  }
  default_arguments = {
    "--job-bookmark-option" = "job-bookmark-enable" # Enable job bookmarking for incremental processing
    "--enable-metrics"      = "true"
    "--TempDir"             = "${var.s3_processed_data_bucket_arn}/glue_temp/"
    "--source_bucket"       = var.s3_raw_logs_bucket_id
    "--target_bucket"       = var.s3_processed_data_bucket_id
    "--source_table"        = "cur_data_table" # Table created by CUR crawler
    "--target_path"         = "processed_egress_costs/"
  }
  worker_type     = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers
  timeout         = 60 # minutes

  tags = {
    Name        = "${var.project_name}-cur-parser-job"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Glue Job for aggregating VPC Flow Logs and extracting features
resource "aws_glue_job" "flow_log_aggregator_job" {
  name            = "${var.project_name}-flow-log-aggregator-job"
  role_arn        = var.glue_iam_role_arn
  command {
    script_location = "${var.s3_model_artifacts_bucket_arn}/glue_scripts/flow_log_aggregator.py" # Script location in S3
    python_version  = "3"
  }
  default_arguments = {
    "--job-bookmark-option" = "job-bookmark-enable"
    "--enable-metrics"      = "true"
    "--TempDir"             = "${var.s3_processed_data_bucket_arn}/glue_temp/"
    "--source_bucket"       = var.s3_raw_logs_bucket_id
    "--target_bucket"       = var.s3_processed_data_bucket_id
    "--source_table"        = "vpc_flow_logs_table" # Table created by Flow Logs crawler
    "--target_path"         = "aggregated_flow_data/"
  }
  worker_type     = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers
  timeout         = 60 # minutes

  tags = {
    Name        = "${var.project_name}-flow-log-aggregator-job"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# --- Amazon Athena (Conceptual) ---
# Athena uses Glue Data Catalog tables to query data directly from S3.
# No explicit Terraform resource for Athena queries, but its functionality
# relies on the Glue Data Catalog setup.

/*
# Example Athena Workgroup (optional, for query isolation/cost control)
resource "aws_athena_workgroup" "egress_optimizer_workgroup" {
  name = "${var.project_name}-workgroup"
  state = "ENABLED"
  configuration {
    result_configuration {
      output_location = "${var.s3_processed_data_bucket_arn}/athena_query_results/"
    }
  }
  tags = {
    Name        = "${var.project_name}-athena-workgroup"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}
*/