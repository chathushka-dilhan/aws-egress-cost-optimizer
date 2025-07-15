# 9. CI/CD Pipeline (GitHub Actions)

This section details the Continuous Integration/Continuous Deployment (CI/CD) pipeline for the AWS Egress Cost Optimizer solution, implemented using GitHub Actions. This pipeline automates the entire deployment lifecycle, ensuring consistency, reliability, and rapid updates.

## 9.1. Overview

The GitHub Actions workflow automates the following key stages:

1. **Build and Validate:** Performs code quality checks, Terraform validation, and Sentinel policy enforcement.
2. **Deploy Infrastructure:** Applies the Terraform plan to provision and update AWS resources.
3. **Deploy Application Code:** Packages and deploys Lambda function code and uploads data processing scripts to S3.

## 9.2. Workflow Trigger

The pipeline is triggered automatically on:

- `push` events to the `main` branch: For changes in `infrastructure/`, `data_processing_scripts/`, `ml_models/`, `application_logic/`, or the pipeline YAML itself. This initiates a full deployment.
- `pull_request` events targeting the `main` branch: For changes in the same paths. This typically runs the `Validate and Plan` stage to ensure proposed changes are compliant before merging.

## 9.3. Pipeline Stages

The workflow is divided into three main stages, each with specific jobs and responsibilities:

![alt text](./diagrams/CICD-Flow.drawio.png "cicd")

### 9.3.1. `ValidateAndPlan` Stage

This stage focuses on ensuring code quality, infrastructure correctness, and policy compliance without making any changes to the AWS environment.

- **Job:** `TerraformPlan`
- **Runs On:** `ubuntu-latest`
- **Steps:**

    - Checkout Code: Clones the repository.
    - Set up Python & Install Dependencies: Prepares the environment for Python-based linting and testing.
    - Lint Python Scripts (Flake8 & Black): Enforces code style and catches common errors.
    - Set up Terraform: Installs the Terraform CLI.
    - Terraform Format Check: Ensures Terraform files are correctly formatted.
    - Terraform Validate: Checks the syntax and configuration of the Terraform code.
    - Install tfsec: Runs static analysis for security misconfigurations in Terraform.
    - Configure AWS Credentials: Uses `aws-actions/configure-aws-credentials` with an OIDC (OpenID Connect) role to securely assume an IAM role in AWS account. This role needs permissions to read AWS resources for `terraform plan`.
    - Terraform Init (for plan): Initializes the Terraform working directory, configuring the S3 backend for state management.
    - Terraform Plan: Generates an execution plan (`tfplan.binary`) and converts it to JSON (`tfplan.json`). This step also passes Terraform variables (including sensitive ones from GitHub Secrets).
    - Install Sentinel CLI: Downloads and installs the HashiCorp Sentinel CLI.
    - Run Sentinel Policies: Executes `sentinel apply` against the generated `tfplan.json` using the policies defined in the `sentinel/` directory. If any policy fails, this step will fail, preventing deployment.
    - Upload Terraform Plan Artifact: Uploads the `tfplan.binary` as a build artifact, which can be downloaded by subsequent stages.

### 9.3.2. `DeployInfrastructure` Stage

This stage is responsible for applying the Terraform plan and provisioning/updating the AWS infrastructure.

- **Job:** `TerraformApply`
- **Depends On:** `ValidateAndPlan` (ensures previous stage succeeded).
- **Condition:** `if: github.ref == 'refs/heads/main' && github.event_name == 'push'` (only runs on pushes to the main branch, not PRs).
- **Environment:** `production` (can be configured with GitHub Environments for protection rules like manual approvals).
- **Steps:**

    - **Checkout Code:** Clones the repository.
    - **Set up Terraform:** Installs the Terraform CLI.
    - **Configure AWS Credentials:** Assumes the same OIDC role as the previous stage, but typically with broader permissions for `terraform apply`.
    - **Download Terraform Plan Artifact:** Downloads the `tfplan.binary` generated in the `ValidateAndPlan` stage.
    - **Terraform Init (for apply):** Re-initializes Terraform.
    - **Terraform Apply:** Executes the `tfplan.binary` with `-auto-approve`, applying the planned infrastructure changes to the AWS account.

### 9.3.3. `DeployApplicationCode` Stage

This stage handles the deployment of serverless application code and data processing scripts.

- **Job:** `FunctionCodeDeployment`
- **Depends On:** `DeployInfrastructure` (ensures infrastructure is ready).
- **Condition:** `if: github.ref == 'refs/heads/main' && github.event_name == 'push'`
- **Environment:** `production`
- **Steps:**

    - **Checkout Code:** Clones the repository.
    - **Set up Python:** Prepares the Python environment.
    - **Configure AWS Credentials:** Assumes the OIDC role with permissions for Lambda and S3.
    - **Build and Deploy Lambda Functions:**

        - Iterates through each Lambda function directory (`application_logic/lambda_functions/`).
        - Installs Python dependencies into a `package/` directory.
        - Zips the `package/` contents along with the `index.py` handler script.
        - Uploads the generated ZIP file to the designated S3 bucket (`lambda-code-bucket`).
        - Uses `aws lambda update-function-code` to update the Lambda function in AWS, pointing to the new S3 object.

    - **Upload Glue and SageMaker Processing Scripts:**

        - Uses `aws s3 cp --recursive` to upload the contents of `data_processing_scripts/glue_scripts/` and `data_processing_scripts/sagemaker_processing_scripts/` to the `model-artifacts-bucket` in S3.
        - Uploads `application_logic/bedrock_prompts/` to the `processed-data-bucket` (or a dedicated prompts bucket).

## 9.4. Setup and Configuration

- **GitHub Repository Secrets:** Configure `AWS_ACCOUNT_ID`, `AWS_OIDC_ROLE_NAME`, `NOTIFICATION_EMAIL`, and `VPC_IDS` as repository secrets.
- **AWS OIDC Role:** Set up an IAM OIDC provider in AWS and create an IAM role that GitHub Actions can assume. This role needs appropriate permissions for each stage (e.g., `AdministratorAccess` for simplicity during development, but least privilege for production).
- **Terraform Backend:** Manually create the S3 bucket and DynamoDB table for Terraform state before the first pipeline run.
- **Environment Variables:** Ensure `env` variables in the YAML (`AWS_REGION`, `TF_STATE_BUCKET`, `S3_BUCKET_SUFFIX`, etc.) match the Terraform configuration.

