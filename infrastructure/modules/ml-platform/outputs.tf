output "sagemaker_notebook_instance_name" {
  description = "Name of the SageMaker Notebook Instance."
  value       = aws_sagemaker_notebook_instance.dev_notebook.name
}

output "sagemaker_model_name" {
  description = "Name of the deployed SageMaker model."
  value       = aws_sagemaker_model.anomaly_detector_model.name
}

output "sagemaker_endpoint_name" {
  description = "Name of the deployed SageMaker endpoint."
  value       = aws_sagemaker_endpoint.anomaly_detector_endpoint.name
}

output "sagemaker_endpoint_arn" {
  description = "ARN of the deployed SageMaker endpoint."
  value       = aws_sagemaker_endpoint.anomaly_detector_endpoint.arn
}