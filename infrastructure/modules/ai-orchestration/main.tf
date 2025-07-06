# This Terraform module sets up the AI-driven orchestration for egress cost anomaly detection and remediation.
# It includes AWS Lambda functions, Step Functions, and necessary IAM roles and policies.

# --- AWS Lambda Functions ---
# These functions drive the intelligent detection, analysis, and orchestration.

# Lambda Function: Anomaly Detector Trigger
# This function will be triggered periodically (e.g., by EventBridge)
# to fetch latest data, prepare it, and invoke the SageMaker anomaly detection endpoint.
resource "aws_lambda_function" "anomaly_detector_trigger" {
  function_name = "${var.project_name}-anomaly-detector-trigger"
  handler       = "index.handler" # Assuming Python handler
  runtime       = "python3.9"
  role          = var.lambda_iam_role_arn
  timeout       = 300 # 5 minutes
  memory_size   = 256

  # Code deployment: Assuming a zip file in S3.
  # This zip file will contain the Lambda code and its dependencies.
  s3_bucket = var.s3_lambda_code_bucket_id
  s3_key    = "lambda_functions/anomaly_detector_trigger.zip" # Update with actual S3 key
  source_code_hash = filebase64sha256("../../application_logic/lambda_functions/anomaly_detector_trigger/anomaly_detector_trigger.zip") # Placeholder for local zip

  environment {
    variables = {
      SAGEMAKER_ENDPOINT_NAME = var.sagemaker_endpoint_name
      PROCESSED_DATA_BUCKET   = var.s3_processed_data_bucket_id
      SNS_ANOMALY_TOPIC_ARN   = var.sns_anomaly_topic_arn # For direct alerts
      STEP_FUNCTION_ARN       = aws_sfn_state_machine.egress_remediation_workflow.arn # Pass Step Function ARN
    }
  }

  tags = {
    Name        = "${var.project_name}-anomaly-detector-trigger"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Lambda Function: Bedrock Analyzer
# This function will be triggered when an anomaly is detected.
# It gathers context (Config, CloudTrail, Cost Explorer) and uses Bedrock LLM for root cause analysis.
resource "aws_lambda_function" "bedrock_analyzer" {
  function_name = "${var.project_name}-bedrock-analyzer"
  handler       = "index.handler"
  runtime       = "python3.9"
  role          = var.bedrock_access_iam_role_arn # Use the Bedrock-specific role
  timeout       = 300
  memory_size   = 512 # LLM interactions might require more memory

  s3_bucket = var.s3_lambda_code_bucket_id
  s3_key    = "lambda_functions/bedrock_analyzer.zip" # Update with actual S3 key
  source_code_hash = filebase64sha256("../../application_logic/lambda_functions/bedrock_analyzer/bedrock_analyzer.zip") # Placeholder for local zip

  environment {
    variables = {
      BEDROCK_MODEL_ID      = var.bedrock_model_id
      SNS_ANOMALY_TOPIC_ARN = var.sns_anomaly_topic_arn # For sending enriched alerts
      PROCESSED_DATA_BUCKET = var.s3_processed_data_bucket_id # For fetching more data if needed
    }
  }

  tags = {
    Name        = "${var.project_name}-bedrock-analyzer"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Lambda Function: Remediation Orchestrator
# This function would be invoked by the Step Function to perform specific remediation actions.
# It needs granular permissions to modify resources based on the action.
resource "aws_lambda_function" "remediation_orchestrator" {
  function_name = "${var.project_name}-remediation-orchestrator"
  handler       = "index.handler"
  runtime       = "python3.9"
  role          = var.lambda_iam_role_arn # Needs permissions to perform remediation actions
  timeout       = 300
  memory_size   = 256

  s3_bucket = var.s3_lambda_code_bucket_id
  s3_key    = "lambda_functions/remediation_orchestrator.zip" # Update with actual S3 key
  source_code_hash = filebase64sha256("../../application_logic/lambda_functions/remediation_orchestrator/remediation_orchestrator.zip") # Placeholder for local zip

  tags = {
    Name        = "${var.project_name}-remediation-orchestrator"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# --- AWS Step Functions State Machine ---
# Orchestrates complex, multi-step remediation processes based on anomaly types.
resource "aws_sfn_state_machine" "egress_remediation_workflow" {
  name     = "${var.project_name}-egress-remediation-workflow"
  role_arn = var.lambda_iam_role_arn # This role needs 'states:*' and 'lambda:InvokeFunction' permissions

  definition = jsonencode({
    Comment = "A State Machine to orchestrate egress cost anomaly remediation workflows."
    StartAt = "CheckAnomalyType"
    States = {
      "CheckAnomalyType" = {
        Type = "Choice",
        Choices = [
          {
            Variable = "$.anomalyType",
            StringEquals = "S3_Public_Access",
            Next = "RemediateS3PublicAccess"
          },
          {
            Variable = "$.anomalyType",
            StringEquals = "OverlyPermissive_SecurityGroup",
            Next = "RemediateSecurityGroup"
          },
          {
            Variable = "$.anomalyType",
            StringEquals = "High_Data_Transfer_EC2",
            Next = "AnalyzeEC2EgressAnomaly"
          }
        ],
        Default = "NotifyManualReview" # Fallback for unhandled anomaly types
      },
      "RemediateS3PublicAccess" = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke", # Standard ARN for invoking Lambda from Step Functions
        Parameters = {
          "FunctionName": aws_lambda_function.remediation_orchestrator.arn,
          "Payload": {
            "action": "remediate_s3_public_access",
            "resourceId": "$.resourceId",
            "anomalyDetails": "$."
          }
        },
        Retry = [{
          ErrorEquals = ["Lambda.Client.RequestTooLargeException", "Lambda.Unknown", "Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          IntervalSeconds = 2,
          MaxAttempts = 6,
          BackoffRate = 2
        }],
        Catch = [{
          ErrorEquals = ["States.ALL"],
          Next = "NotifyRemediationFailure"
        }],
        End = true
      },
      "RemediateSecurityGroup" = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName": aws_lambda_function.remediation_orchestrator.arn,
          "Payload": {
            "action": "remediate_security_group",
            "resourceId": "$.resourceId",
            "anomalyDetails": "$."
          }
        },
        Retry = [{
          ErrorEquals = ["Lambda.Client.RequestTooLargeException", "Lambda.Unknown", "Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          IntervalSeconds = 2,
          MaxAttempts = 6,
          BackoffRate = 2
        }],
        Catch = [{
          ErrorEquals = ["States.ALL"],
          Next = "NotifyRemediationFailure"
        }],
        End = true
      },
      "AnalyzeEC2EgressAnomaly" = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName": aws_lambda_function.bedrock_analyzer.arn,
          "Payload": {
            "resourceId": "$.resourceId",
            "anomalyType": "$.anomalyType",
            "costImpact": "$.costImpact",
            "context": "$." # Pass the entire input for Bedrock to analyze
          }
        },
        Retry = [{
          ErrorEquals = ["Lambda.Client.RequestTooLargeException", "Lambda.Unknown", "Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          IntervalSeconds = 2,
          MaxAttempts = 6,
          BackoffRate = 2
        }],
        Catch = [{
          ErrorEquals = ["States.ALL"],
          Next = "NotifyAnalysisFailure"
        }],
        End = true # Or transition to another state if further action is needed based on analysis
      },
      "NotifyManualReview" = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          "TopicArn": var.sns_anomaly_topic_arn,
          "Message": "{\"Subject\": \"Egress Anomaly: Manual Review Required\", \"Message\": \"Anomaly Type: $.anomalyType, Resource ID: $.resourceId, Cost Impact: $.costImpact. Full details: $.\"}"
        },
        ResultPath = null, # Discard output of SNS publish
        End = true
      },
      "NotifyRemediationFailure" = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          "TopicArn": var.sns_anomaly_topic_arn,
          "Message": "{\"Subject\": \"Egress Remediation Failed\", \"Message\": \"Remediation failed for anomaly type: $.anomalyType, Resource ID: $.resourceId. Error: $.Error. Cause: $.Cause. Full details: $.\"}"
        },
        ResultPath = null,
        End = true
      },
      "NotifyAnalysisFailure" = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          "TopicArn": var.sns_anomaly_topic_arn,
          "Message": "{\"Subject\": \"Egress Anomaly Analysis Failed\", \"Message\": \"Analysis failed for anomaly type: $.anomalyType, Resource ID: $.resourceId. Error: $.Error. Cause: $.Cause. Full details: $.\"}"
        },
        ResultPath = null,
        End = true
      }
    }
  })

  tags = {
    Name        = "${var.project_name}-egress-remediation-workflow"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# --- CloudWatch Event Rule to trigger Anomaly Detector Trigger Lambda periodically ---
resource "aws_cloudwatch_event_rule" "anomaly_detection_schedule" {
  name                = "${var.project_name}-anomaly-detection-schedule"
  description         = "Triggers the anomaly detector Lambda periodically."
  schedule_expression = "rate(1 hour)" # Run every hour (adjust frequency as needed)

  tags = {
    Name        = "${var.project_name}-anomaly-detection-schedule"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_cloudwatch_event_target" "anomaly_detector_trigger_target" {
  rule      = aws_cloudwatch_event_rule.anomaly_detection_schedule.name
  target_id = "AnomalyDetectorTriggerLambda"
  arn       = aws_lambda_function.anomaly_detector_trigger.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_invoke_anomaly_detector" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomaly_detector_trigger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.anomaly_detection_schedule.arn
}