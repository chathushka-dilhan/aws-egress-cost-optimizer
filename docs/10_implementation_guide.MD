# 10. Implementation Guide

This guide provides a step-by-step walkthrough to deploy and configure the AWS Egress Cost Optimizer solution in your AWS account. Follow these instructions carefully to ensure a successful deployment.

## 10.1. Prerequisites

Before begin, ensure you have the following:

- **AWS Account:** An active AWS account with administrative privileges to create all necessary resources.
- **AWS CLI:** Installed and configured with credentials for the target AWS account and region.
- **Git:** Installed to clone the repository.
- **Terraform:** Installed (v1.0.0+ recommended).
- **Python:** Python 3.9+ installed locally.
- **Docker:** Installed (if plan to build custom SageMaker Docker images, though not strictly required for this solution's default built-in algorithms).
- **Node.js & npm (Optional):** If you plan to use `cdk` for local testing or custom Lambda packaging.
- **Basic AWS Knowledge:** Familiarity with AWS services like S3, IAM, Lambda, SageMaker, Glue, and CloudWatch.

## 10.2. Initial Setup Steps (Manual - One-Time)

These steps involve configurations that typically cannot be fully automated via Terraform or are account-wide settings.

### 10.2.1. Enable AWS Cost and Usage Reports (CUR)

CUR is essential for granular cost data.

1. Go to the AWS Billing dashboard: https://console.aws.amazon.com/billing/
2. In the left navigation pane, choose **Cost & Usage Reports.**
3. Click **Create report**.
4. **Report name:** `EgressCostOptimizerReport` (or a name of your choice).
5. **Additional report details:**

    - Select Include resource IDs (CRITICAL).
    - Select Enable resource tags (Highly Recommended).
    - Optionally, select "Include public pricing".

6. **S3 bucket:** You will select the S3 bucket that Terraform will create for raw logs (e.g., `egress-cost-optimizer-raw-logs-SUFFIX`). **For the first time, you might need to create a temporary S3 bucket manually here, then update it to the Terraform-created bucket after** `terraform apply`.
7. **Report path prefix:** `egress-cur/` (or a prefix of choice). Remember this prefix as you'll need it for the Glue Crawler configuration in Terraform.
8. **Time granularity:** Hourly (CRITICAL for detailed analysis).
9. **Report versioning:** `Overwrite existing report` (recommended).
10. **Data refresh settings:** `Enable automatic refreshes`.
11. Click **Next** and then **Review and create**.

### 10.2.2. Set up Amazon QuickSight User

If you haven't used QuickSight before, you need to set up an account and user.

1. Go to the Amazon QuickSight console: https://console.aws.amazon.com/quicksight/
2. If it's your first time, click **Sign up for QuickSight**.
3. Choose your edition (Standard or Enterprise - Enterprise offers more features like row-level security).
4. Configure your QuickSight account details.
5. Crucially, in the "AWS services" section during setup, ensure you grant QuickSight access to:

    - **Amazon S3:** Select the S3 buckets created by Terraform for raw logs and processed data (e.g., `egress-cost-optimizer-raw-logs-SUFFIX` and `egress-cost-optimizer-processed-data-SUFFIX`).
    - **Amazon Athena:** Grant access to Athena.
    - **AWS Glue:** Grant access to AWS Glue Data Catalog.

6. Complete the sign-up process.

### 10.2.3. Create Terraform State Backend Resources

Before running Terraform, you need an S3 bucket and DynamoDB table for state management.

1. Create S3 Bucket:

    ```bash
    aws s3 mb s3://tfstate-egress-cost-optimizer-<AWS_ACCOUNT_ID> --region us-east-1 # Use your account ID for uniqueness
    aws s3api put-bucket-versioning --bucket tfstate-egress-cost-optimizer-<AWS_ACCOUNT_ID> --versioning-configuration Status=Enabled
    ```

2. Create DynamoDB Table:

    ```bash
    aws dynamodb create-table \
        --table-name tfstate-egress-cost-optimizer-locks \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region us-east-1
    ```

3. Update `infrastructure/versions.tf`: Replace `tfstate-egress-cost-optimizer-YOUR_ACCOUNT_ID` and `tfstate-egress-cost-optimizer-locks` with your actual bucket and table names.

### 10.2.4. Configure AWS OIDC Role for GitHub Actions

This is critical for secure CI/CD.

1. **Create IAM OIDC Provider:**

    - Go to IAM > Identity providers > Add provider.
    - Choose `OpenID Connect`.
    - Provider URL: `https://token.actions.githubusercontent.com`
    - Audience: `sts.amazonaws.com`
    - Click `Add provider`.

2. **Create IAM Role:**

    - Go to IAM > Roles > Create role.
    - Select `Web identity`.
    - Choose the OIDC provider you just created.
    - For Audience, select `sts.amazonaws.com`.
    - Attach policies that grant the necessary permissions for Terraform to deploy your infrastructure. For initial setup `AdministratorAccess` can be used, but for production, create a custom policy with least privilege.
    - Give the role a name (e.g., `github-actions-egress-optimizer-role`).
    - Update Trust Policy: Edit the Trust Policy to restrict it to your specific GitHub repository:

        ```json
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                "Effect": "Allow",
                "Principal": {
                    "Federated": "arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:*"
                    },
                    "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                    }
                }
                }
            ]
        }
        ```

        Replace placeholders.

## 10.3. Repository Setup and Configuration

### 10.3.1. Clone the Repository

```bash
git clone https://github.com/your-org/aws-egress-cost-optimizer.git
cd aws-egress-cost-optimizer
```

### 10.3.2. Configure Terraform Variables

Create `terraform.tfvars` in the `infrastructure/` directory and populate it with your specific values.

```bash
cd infrastructure/
touch terraform.tfvars
```

Edit `terraform.tfvars`:

```terraform
# infrastructure/terraform.tfvars

project_name = "egress-cost-optimizer"
aws_region   = "us-east-1" # Must match your chosen region
environment_tag = "dev"
owner_tag = "finops-team"

s3_bucket_suffix = "youruniquesuffix123" # IMPORTANT: Change this to a truly unique string!

vpc_ids = ["vpc-xxxxxxxxxxxxxxxxx", "vpc-yyyyyyyyyyyyyyyyy"] # IMPORTANT: Your actual VPC IDs

notification_email = "your-email@example.com" # IMPORTANT: Your actual email for SNS alerts

# CloudFront origin for example distribution (e.g., an existing S3 bucket or ALB)
cloudfront_origin_domain_name = "your-cloudfront-origin.example.com" # IMPORTANT: Your CloudFront origin
```

### 10.3.3. Configure GitHub Repository Secrets

In your GitHub repository, go to **Settings > Secrets and variables > Actions > Repository secrets**.

- `AWS_ACCOUNT_ID`: Your AWS Account ID.
- `AWS_OIDC_ROLE_NAME`: The name of the IAM role you created (e.g., `github-actions-egress-optimizer-role`).
- `NOTIFICATION_EMAIL`: The email address for SNS notifications (if not hardcoded in `terraform.tfvars`).
- `VPC_IDS`: Your VPC IDs as a JSON string (e.g., `["vpc-xxxxxxxxxxxxxxxxx", "vpc-yyyyyyyyyyyyyyyyy"]`).

### 10.3.4. Create GitHub Actions Workflow File

Create the `.github/workflows/main.yml` file with the content provided in the CI/CD Pipeline (GitHub Actions) documentation (a sample yml file is alredy provided in the `ci_cd/` directory).

## 10.4. Deploying the Solution

Once all prerequisites and configurations are complete, deploy the solution via GitHub Actions.

1. **Commit and Push:**

    Commit all your changes and push them to the `main` branch of your GitHub repository.

```bash
git add .
git commit -m "Initial commit: Deploy AWS Egress Cost Optimizer"
git push origin main
```

2. **Monitor Pipeline:**

    Go to your GitHub repository -> **Actions** tab. You will see a workflow run triggered. Monitor its progress.

    - The `Validate and Plan` stage will run first, including Sentinel policy checks.
    - If successful, the `Deploy Infrastructure` stage will apply the Terraform plan.
    - Finally, the `Deploy Application Code` stage will package and deploy your Lambda functions and upload data processing scripts.

3. **Confirm SNS Subscription:**

    After the pipeline successfully deploys, check the email address you provided for notification_email. You will receive a subscription confirmation email from AWS SNS. You must click the confirmation link in this email to receive alerts.

## 10.5. Post-Deployment Configuration & Verification

### 10.5.1. Verify S3 Buckets and Logs

- Check your AWS S3 console. You should see `egress-cost-optimizer-raw-logs-SUFFIX`, `egress-cost-optimizer-processed-data-SUFFIX`, `egress-cost-optimizer-ml-model-artifacts-SUFFIX`, and `egress-cost-optimizer-lambda-code-SUFFIX`.
- Ensure VPC Flow Logs are being delivered to the `raw_logs` bucket (check the `vpc_flow_logs/ prefix`).
- Verify CUR reports are being delivered to the `raw_logs` bucket (check your `egress-cur/` prefix).

### 10.5.2. Upload Data Processing Scripts

The CI/CD pipeline should have handled this, but verify the scripts are in S3:

- `s3://<MODEL_ARTIFACTS_BUCKET>/glue_scripts/cur_parser.py`
- `s3://<MODEL_ARTIFACTS_BUCKET>/glue_scripts/flow_log_aggregator.py`
- `s3://<MODEL_ARTIFACTS_BUCKET>/sagemaker_processing_scripts/feature_engineering.py`
- `s3://<PROCESSED_DATA_BUCKET>/bedrock_prompts/egress_root_cause_prompt.txt`

### 10.5.3. Manually Trigger Glue Crawlers (Initial Run)

For the first time, you might need to manually run the Glue Crawlers to populate the Data Catalog.

1. Go to AWS Glue console -> **Crawlers**.
2. Select `egress-cost-optimizer-vpc-flow-logs-crawler` and `egress-cost-optimizer-cur-crawler`.
3. Click **Run crawler**.
4. Verify that tables (e.g., `cur_data_table`, `vpc_flow_logs_table`) appear in the Glue Data Catalog under the `egress_cost_optimizer_raw_logs_db` database.

### 10.5.4. Run Glue ETL Jobs (Initial Data Processing)

After crawlers, run the Glue ETL jobs.

1. Go to AWS Glue console -> **Jobs**.
2. Select `egress-cost-optimizer-cur-parser-job` and `egress-cost-optimizer-flow-log-aggregator-job`.
3. Click **Run job**.
4. Monitor job status and verify that processed data appears in your processed_data S3 bucket (e.g., `processed_egress_costs/`, `aggregated_flow_data/` prefixes).

### 10.5.5. Train SageMaker Model (First Time)

The SageMaker model is defined by Terraform, but the training job needs to be triggered. This can be done via a SageMaker Notebook or a separate pipeline step.

1. Go to SageMaker console -> **Notebook instances**.
2. Open `egress-cost-optimizer-dev-notebook`.
3. Navigate to `ml_models/anomaly_detection/notebooks/model_training.ipynb`.
4. Run the cells in the notebook to trigger a SageMaker training job. This will train your anomaly detection model and upload `model.tar.gz` to your `model_artifacts` S3 bucket.
5. Verify that the `egress-anomaly-detector-endpoint` is in InService status under SageMaker -> **Endpoints**.

### 10.5.6. Verify Lambda Functions

- Go to AWS Lambda console. Check the `egress-cost-optimizer-anomaly-detector-trigger`, `egress-cost-optimizer-bedrock-analyzer`, and `egress-cost-optimizer-remediation-orchestrator` functions.
- Check their `Configuration` -> `Environment variables` to ensure all necessary variables are correctly set (e.g., SageMaker endpoint name, Bedrock model ID, SNS Topic ARN).
- Check `Monitoring` -> `Logs` for any initial errors.

### 10.5.7. Test End-to-End Flow (Simulated)

Use the `simulate_egress_data.py` script to generate some data with anomalies and observe the pipeline.

1. Generate simulated data (as described in [Utility Scripts](08_utility_scripts.MD)).
2. Wait for Glue Crawlers to run (or trigger manually).
3. Wait for Glue ETL jobs to run (or trigger manually).
4. Wait for the `anomaly-detector-trigger` Lambda to run (scheduled hourly by EventBridge).
5. Monitor CloudWatch Logs for the `anomaly-detector-trigger` Lambda and the `egress-remediation-workflow` Step Function executions.
6. Check your SNS-subscribed email for anomaly alerts and remediation status updates.

## 10.6. Troubleshooting

- **Terraform Errors:** Check the GitHub Actions logs for detailed error messages. Ensure all variables are correctly set and IAM permissions are sufficient.
- **Lambda Errors:** Check CloudWatch Logs for the specific Lambda function. Look for Python tracebacks.
- **Glue Job Failures:** Check Glue job logs in CloudWatch for Spark errors or script issues.
- **SageMaker Endpoint Issues:** Check SageMaker endpoint logs in CloudWatch. Ensure the model artifact path is correct and the `inference_script.py` can load the model and process inputs.
- **Permissions:** Most common issues are due to insufficient IAM permissions. Review the IAM roles associated with each service and ensure they have the necessary actions on the correct resources.

