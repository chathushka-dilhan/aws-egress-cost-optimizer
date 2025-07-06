output "glue_raw_logs_database_name" {
  description = "Name of the Glue Data Catalog database for raw logs."
  value       = aws_glue_catalog_database.raw_logs_db.name
}

output "glue_processed_data_database_name" {
  description = "Name of the Glue Data Catalog database for processed data."
  value       = aws_glue_catalog_database.processed_data_db.name
}

output "cur_parser_job_name" {
  description = "Name of the Glue job for CUR parsing."
  value       = aws_glue_job.cur_parser_job.name
}

output "flow_log_aggregator_job_name" {
  description = "Name of the Glue job for flow log aggregation."
  value       = aws_glue_job.flow_log_aggregator_job.name
}