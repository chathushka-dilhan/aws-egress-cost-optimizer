output "lambda_anomaly_detector_trigger_name" {
  description = "Name of the Lambda function that triggers anomaly detection."
  value       = aws_lambda_function.anomaly_detector_trigger.function_name
}

output "lambda_bedrock_analyzer_name" {
  description = "Name of the Lambda function that interacts with Bedrock."
  value       = aws_lambda_function.bedrock_analyzer.function_name
}

output "lambda_remediation_orchestrator_name" {
  description = "Name of the Lambda function that orchestrates remediation."
  value       = aws_lambda_function.remediation_orchestrator.function_name
}

output "step_function_state_machine_arn" {
  description = "ARN of the Step Functions State Machine for egress remediation."
  value       = aws_sfn_state_machine.egress_remediation_workflow.arn
}
