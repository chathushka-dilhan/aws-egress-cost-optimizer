# This Terraform module sets up core AWS services for the AWS egress cost optimization solution.
# It includes S3 buckets for data storage, IAM roles for service permissions, and CloudWatch log groups for logging.

# --- S3 Buckets ---
# These buckets are central storage locations for various data types and artifacts.

# S3 bucket for raw logs (VPC Flow Logs, S3 Access Logs, CloudFront Logs, CUR)
resource "aws_s3_bucket" "raw_logs" {
  bucket = "${var.project_name}-raw-logs-${var.s3_bucket_suffix}"

  tags = {
    Name        = "${var.project_name}-raw-logs"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_s3_bucket_acl" "raw_logs_acl" {
  bucket = aws_s3_bucket.raw_logs.id
  acl    = "private"
}

# Enable versioning for raw logs bucket (good for data integrity and recovery)
resource "aws_s3_bucket_versioning" "raw_logs_versioning" {
  bucket = aws_s3_bucket.raw_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enforce server-side encryption for raw logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_logs_encryption" {
  bucket = aws_s3_bucket.raw_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Or "aws:kms" for KMS-managed keys
    }
  }
}

# S3 bucket for processed (cleaned, aggregated, feature-engineered) data
resource "aws_s3_bucket" "processed_data" {
  bucket = "${var.project_name}-processed-data-${var.s3_bucket_suffix}"

  tags = {
    Name        = "${var.project_name}-processed-data"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_s3_bucket_acl" "processed_data_acl" {
  bucket = aws_s3_bucket.processed_data.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "processed_data_versioning" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data_encryption" {
  bucket = aws_s3_bucket.processed_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for ML model artifacts (trained models, pre-processing scripts for SageMaker)
resource "aws_s3_bucket" "model_artifacts" {
  bucket = "${var.project_name}-ml-model-artifacts-${var.s3_bucket_suffix}"

  tags = {
    Name        = "${var.project_name}-ml-model-artifacts"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_s3_bucket_acl" "model_artifacts_acl" {
  bucket = aws_s3_bucket.model_artifacts.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "model_artifacts_versioning" {
  bucket = aws_s3_bucket.model_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts_encryption" {
  bucket = aws_s3_bucket.model_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for Lambda function deployment packages
resource "aws_s3_bucket" "lambda_code" {
  bucket = "${var.project_name}-lambda-code-${var.s3_bucket_suffix}"

  tags = {
    Name        = "${var.project_name}-lambda-code"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_s3_bucket_acl" "lambda_code_acl" {
  bucket = aws_s3_bucket.lambda_code.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "lambda_code_versioning" {
  bucket = aws_s3_bucket.lambda_code.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_code_encryption" {
  bucket = aws_s3_bucket.lambda_code.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- IAM Roles ---
# These roles provide necessary permissions for different AWS services to interact.

# IAM Role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-firehose-role"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Policy for Firehose to write to S3 and CloudWatch Logs
resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        Resource = [
          aws_s3_bucket.raw_logs.arn,
          "${aws_s3_bucket.raw_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:${aws_cloudwatch_log_group.firehose_log_group.name}:*"
      }
    ]
  })
}

# IAM Role for AWS Glue (ETL jobs, Crawlers)
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-glue-role"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Attach AWS managed policy for Glue service role
resource "aws_iam_role_policy_attachment" "glue_service_policy_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for Glue to read/write S3 buckets
resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${var.project_name}-glue-s3-policy"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject" # For temporary files or cleanup
        ],
        Resource = [
          aws_s3_bucket.raw_logs.arn,
          "${aws_s3_bucket.raw_logs.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.model_artifacts.arn, # For Glue to potentially read/write ML related data
          "${aws_s3_bucket.model_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# IAM Role for Amazon SageMaker
resource "aws_iam_role" "sagemaker_role" {
  name = "${var.project_name}-sagemaker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-sagemaker-role"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Attach AWS managed policies for SageMaker
resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" # Broad for simplicity, refine as needed
}

# Custom policy for SageMaker to access S3 buckets
resource "aws_iam_role_policy" "sagemaker_s3_policy" {
  name = "${var.project_name}-sagemaker-s3-policy"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.model_artifacts.arn,
          "${aws_s3_bucket.model_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets"
        ],
        Resource = "*"
      }
    ]
  })
}

# IAM Role for AWS Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-role"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda to access S3, SageMaker, Bedrock, SNS
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${var.project_name}-lambda-custom-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.lambda_code.arn,
          "${aws_s3_bucket.lambda_code.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "sagemaker:InvokeEndpoint"
        ],
        Resource = "arn:aws:sagemaker:${var.aws_region}:${var.aws_account_id}:endpoint/*" # Refine to specific endpoint later
      },
      {
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = "arn:aws:sns:${var.aws_region}:${var.aws_account_id}:*" # Refine to specific SNS topic later
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = "*" # Bedrock actions are often broad, but can be refined by model ARN if needed
      },
      {
        Effect = "Allow",
        Action = [
          "config:SelectResourceConfig",
          "config:GetResourceConfigHistory"
        ],
        Resource = "*" # For querying AWS Config for context
      },
      {
        Effect = "Allow",
        Action = [
          "cloudtrail:LookupEvents"
        ],
        Resource = "*" # For querying CloudTrail for context
      },
      {
        Effect = "Allow",
        Action = [
          "ce:GetCostAndUsage"
        ],
        Resource = "*" # For querying Cost Explorer for context
      }
    ]
  })
}

# IAM Role for Bedrock Access (if separate role needed for specific Bedrock interactions)
# Often, the Lambda role itself is sufficient if it has bedrock:InvokeModel.
# This is here for explicit separation if desired.
resource "aws_iam_role" "bedrock_access_role" {
  name = "${var.project_name}-bedrock-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com" # Or other service that will assume this role
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-bedrock-access-role"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_iam_role_policy" "bedrock_invoke_policy" {
  name = "${var.project_name}-bedrock-invoke-policy"
  role = aws_iam_role.bedrock_access_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = "*" # Can be refined to specific model ARNs if known
      }
    ]
  })
}

# IAM Role for QuickSight (if used for dashboards)
resource "aws_iam_role" "quicksight_role" {
  name = "${var.project_name}-quicksight-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-quicksight-role"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

# Policy for QuickSight to access S3 and Athena
resource "aws_iam_role_policy" "quicksight_data_access_policy" {
  name = "${var.project_name}-quicksight-data-access-policy"
  role = aws_iam_role.quicksight_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.raw_logs.arn, # For CUR reports if QuickSight reads them directly
          "${aws_s3_bucket.raw_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:ListQueryExecutions"
        ],
        Resource = "*" # Athena actions are often broad
      },
      {
        Effect = "Allow",
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartition"
        ],
        Resource = "*" # Glue Data Catalog access for Athena
      }
    ]
  })
}

# --- CloudWatch Log Groups ---
# Centralized logging for various services.

resource "aws_cloudwatch_log_group" "firehose_log_group" {
  name              = "/aws/kinesisfirehose/${var.project_name}-flow-logs-delivery"
  retention_in_days = 30 # Adjust retention as needed

  tags = {
    Name        = "${var.project_name}-firehose-logs"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_cloudwatch_log_group" "sagemaker_log_group" {
  name              = "/aws/sagemaker/Endpoints/${var.project_name}-anomaly-detector-endpoint" # Matches SageMaker endpoint name
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-sagemaker-logs"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_cloudwatch_log_group" "glue_log_group" {
  name              = "/aws/glue/jobs/${var.project_name}-etl-job" # Generic name for Glue jobs
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-glue-logs"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.project_name}-lambda-functions" # Generic name for Lambda functions
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-lambda-logs"
    Environment = var.environment_tag
    Owner       = var.owner_tag
  }
}