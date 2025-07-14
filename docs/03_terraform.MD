# 3. Infrastructure (Terraform)

This section details the AWS infrastructure provisioned for the AWS Egress Cost Optimizer solution using Terraform. The infrastructure is organized into modular components for clarity, reusability, and maintainability.

## 3.1. Root Terraform Configuration

The root Terraform files (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`) orchestrate the deployment of the entire solution by calling various child modules.

- `main.tf`:

    - Defines the overall structure of the solution.
    - Calls each of the specialized modules (e.g., `core-aws-services`, `data-ingestion`, `ml-platform`, etc.).
    - Passes necessary variables and outputs between modules, managing dependencies.

- `variables.tf`:

    - Declares all input variables required for the entire Terraform deployment.
    - Includes general project settings, AWS region, tagging conventions, and specific configurations for S3 buckets, VPCs, SageMaker, Bedrock, and Glue.
    - Crucially, this is where you customize values like `aws_region`, `s3_bucket_suffix`, `vpc_ids`, and `notification_email` before deployment.

- `outputs.tf`:

    - Defines the output values from the Terraform deployment.
    - Provides important IDs, ARNs, and names of deployed resources (e.g., S3 bucket names, SNS topic ARNs, SageMaker endpoint names) that might be needed for external integrations or verification.

- `providers.tf`:

    - Configures the AWS provider, specifying the AWS region.
    - Includes a data `"aws_caller_identity"` block to dynamically retrieve the current AWS account ID, which is used in IAM policies and resource ARNs.

- `versions.tf`:

    - Specifies the required Terraform CLI version and AWS provider version.
    - Configures the S3 backend for Terraform state management, ensuring state persistence and locking for collaborative development. Note: The S3 bucket and DynamoDB table for the backend must be created manually once before the first `terraform init`.

## 3.2. Terraform Modules

Each module is a self-contained set of Terraform configurations responsible for provisioning a specific logical component of the solution.

### 3.2.1. `core-aws-services/`

This module provisions the foundational AWS resources that are prerequisites for almost all other components.

- **S3 Buckets:**

    - `aws_s3_bucket.raw_logs`: Stores all raw log data (VPC Flow Logs, S3 Access Logs, CloudFront Logs, CUR). Configured with private ACLs, versioning, and server-side encryption (AES256).
    - `aws_s3_bucket.processed_data`: Stores cleaned, aggregated, and feature-engineered data. Also configured with private ACLs, versioning, and encryption.
    - `aws_s3_bucket.model_artifacts`: Stores trained ML models, pre-processing scripts, and other SageMaker artifacts. Configured with private ACLs, versioning, and encryption.
    - `aws_s3_bucket.lambda_code`: Stores deployment packages (ZIP files) for AWS Lambda functions. Configured with private ACLs, versioning, and encryption.

- **IAM Roles & Policies:**

    - `aws_iam_role.firehose_role`: For Kinesis Data Firehose to deliver logs to S3 and CloudWatch Logs.
    - `aws_iam_role.glue_role`: For AWS Glue ETL jobs and crawlers to access S3 data and interact with the Glue Data Catalog.
    - `aws_iam_role.sagemaker_role`: For Amazon SageMaker to access S3 for data/model artifacts and perform ML operations.
    - `aws_iam_role.lambda_role`: A generic role for AWS Lambda functions, granting basic execution, S3 access, SageMaker invocation, SNS publishing, and permissions for AWS Config, CloudTrail, and Cost Explorer lookups.
    - `aws_iam_role.bedrock_access_role`: A dedicated role for Bedrock interactions, often assumed by Lambda functions.
    - `aws_iam_role.quicksight_role`: For Amazon QuickSight to access data in S3 via Athena/Glue.

- **CloudWatch Log Groups:**

    - `aws_cloudwatch_log_group.firehose_log_group`: For Kinesis Data Firehose delivery logs.
    - `aws_cloudwatch_log_group.sagemaker_log_group`: For SageMaker endpoint logs.
    - `aws_cloudwatch_log_group.glue_log_group`: For AWS Glue job logs.
    - `aws_cloudwatch_log_group.lambda_log_group`: For AWS Lambda function logs.

### 3.2.2. `data-ingestion/`

This module configures the mechanisms for collecting raw data from various AWS sources.

- **Kinesis Data Firehose Delivery Stream** (`aws_kinesis_firehose_delivery_stream.vpc_flow_logs_stream`):

    - Sets up a Firehose stream to deliver VPC Flow Logs to the raw_logs S3 bucket.
    - Configured with GZIP compression and CloudWatch logging.

- **VPC Flow Logs** (`aws_vpc_flow_log.vpc_flow_logs`):

    - Iterates through a list of provided VPC IDs to enable VPC Flow Logs for each, directing them to the Firehose stream.

- **S3 Bucket Access Logging** (`aws_s3_bucket_logging.raw_logs_access_logging`):

    - Enables access logging for the raw_logs S3 bucket itself, storing logs within the same bucket for auditing.

- **CloudFront Distribution** (`aws_cloudfront_distribution.example_cloudfront_distribution`):

    - Provisions a sample CloudFront distribution.
    - Configures its logging_config to send access logs to the raw_logs S3 bucket, enabling analysis of CDN-related egress.

### 3.2.3. `etl-processing/`

This module sets up AWS Glue resources for transforming raw logs into a structured, queryable format.

- **AWS Glue Data Catalog Databases:**

    - `aws_glue_catalog_database.raw_logs_db`: A database in the Glue Data Catalog for tables representing raw log data.
    - `aws_glue_catalog_database.processed_data_db`: A database for tables representing cleaned and aggregated data.

- **AWS Glue Crawlers:**

    - `aws_glue_crawler.vpc_flow_logs_crawler`: Automatically discovers schema from VPC Flow Logs in S3 and populates the raw_logs_db. Scheduled to run daily.
    - `aws_glue_crawler.cur_crawler`: Discovers schema from AWS Cost and Usage Reports (CUR) in S3 and populates the raw_logs_db. Scheduled to run daily. Requires CUR to be enabled and configured to deliver to the raw logs S3 bucket.

- **AWS Glue Jobs:**

    - `aws_glue_job.cur_parser_job`: An ETL job that processes CUR data, filters for egress costs, and aggregates them. The script location is specified from the model_artifacts S3 bucket.
    - `aws_glue_job.flow_log_aggregator_job`: An ETL job that processes VPC Flow Logs, identifies egress traffic, and aggregates relevant features. The script location is also from the model_artifacts S3 bucket.

### 3.2.4. `ml-platform/`

This module deploys Amazon SageMaker resources for training and deploying the anomaly detection model.

- **SageMaker Notebook Instance** (`aws_sagemaker_notebook_instance.dev_notebook`):

    - Provisions a Jupyter notebook environment for interactive development and experimentation.
    - Includes a lifecycle configuration to set up the environment (e.g., install libraries, clone Git repos).

- **SageMaker Model Package Group** (`aws_sagemaker_model_package_group.anomaly_detector_mpg`):

    - Enables versioning and management of different iterations of the trained anomaly detection models.

- **SageMaker Model** (`aws_sagemaker_model.anomaly_detector_model`):

    - Defines the machine learning model, pointing to the trained model artifact (model.tar.gz) in the model_artifacts S3 bucket.
    - Uses a built-in SageMaker algorithm image (e.g., Random Cut Forest).

- **SageMaker Endpoint Configuration** (`aws_sagemaker_endpoint_configuration.anomaly_detector_ep_config`):

    - Specifies the instance types and count for the SageMaker inference endpoint that will host the model.

- **SageMaker Endpoint** (`aws_sagemaker_endpoint.anomaly_detector_endpoint`):

    - Deploys the SageMaker model as a real-time inference endpoint, allowing other services (like Lambda) to send data and receive anomaly predictions.

### 3.2.5. `ai-orchestration/`

This module configures AWS Lambda functions for triggering SageMaker inference, interacting with Bedrock for root cause analysis, and orchestrating remediation actions, all coordinated by AWS Step Functions.

- **AWS Lambda Functions:**

    - `aws_lambda_function.anomaly_detector_trigger`: Triggered by EventBridge. Fetches the latest processed data, invokes the SageMaker anomaly detection endpoint, and, if anomalies are found, triggers the egress_remediation_workflow Step Function.
    - `aws_lambda_function.bedrock_analyzer`: Triggered by Step Functions. Gathers contextual data from AWS Config, CloudTrail, and Cost Explorer. It then invokes an LLM via Amazon Bedrock to perform root cause analysis and generate recommendations.
    - `aws_lambda_function.remediation_orchestrator`: Triggered by Step Functions. Executes specific, predefined automated remediation actions (e.g., blocking public S3 access, revoking overly permissive security group rules).

- **AWS Step Functions State Machine** (`aws_sfn_state_machine.egress_remediation_workflow`):

    - Orchestrates complex, multi-step remediation processes.
    - Uses a `Choice` state to route anomalies based on their `anomalyType` (e.g., "S3_Public_Access", "OverlyPermissive_SecurityGroup", "High_Data_Transfer_EC2").
    - Invokes the `Bedrock Analyzer` Lambda for analysis or the `Remediation Orchestrator` Lambda for direct remediation.
    - Includes `Retry` and `Catch` mechanisms for robustness and error handling.
    - Notifies an SNS topic on success, failure, or manual review requirements.

- **CloudWatch Event Rule** (`aws_cloudwatch_event_rule.anomaly_detection_schedule`):

    - Schedules the `anomaly_detector_trigger` Lambda to run periodically (e.g., hourly) to initiate the anomaly detection process.

### 3.2.6. `monitoring-alerting/`

This module sets up SNS topics for notifications and CloudWatch Alarms for high-level egress cost anomalies, and configures QuickSight data sources.

- **Amazon SNS Topic** (`aws_sns_topic.anomaly_alerts_topic`):

    - A central notification topic for all anomaly alerts, remediation statuses (success/failure), and critical system messages.
    - Includes an email subscription for immediate notifications.

- **AWS CloudWatch Metric Alarm** (`aws_cloudwatch_metric_alarm.high_egress_cost_alarm`):

    - A high-level alarm on AWS Cost Explorer's "BlendedCost" metric.
    - Triggers if daily egress cost exceeds a configurable threshold, providing a safety net.

- **Amazon QuickSight Data Source** (`aws_quicksight_data_source.egress_data_source`):

    - Configures a QuickSight data source to connect to Athena, allowing QuickSight to query the processed data in S3 via the Glue Data Catalog.
    - Grants necessary permissions for QuickSight to describe and create datasets based on this data source.
    - <code style="color : red"> **Note:** Actual QuickSight dashboards and analyses are typically created manually within the QuickSight console, leveraging this data source.</code>


