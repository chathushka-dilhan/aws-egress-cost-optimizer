# 4. Sentinel Policies

This section details the HashiCorp Sentinel policies used to enforce governance and security best practices on AWS infrastructure before it is deployed. These policies act as guardrails, validating the Terraform plans to ensure compliance with the organizational standards.

## 4.1. Policy Enforcement Overview

Sentinel policies are integrated into the CI/CD pipeline (specifically in the `build-and-validate` stage of the GitHub Actions workflow). During the `terraform plan` phase, the generated plan is evaluated against these policies. If any policy fails, the pipeline will halt, preventing the deployment of non-compliant resources.

This "shift-left" approach helps to:

- **Prevent Misconfigurations:** Catch security vulnerabilities or compliance violations early in the development lifecycle.
- **Enforce Standards:** Ensure consistent application of naming conventions, tagging, encryption, and network security rules.
- **Reduce Remediation Cost:** Fixing issues in the planning phase is significantly cheaper and less disruptive than remediating them in deployed production environments.
- **Automate Compliance Checks:** Provide continuous, automated auditing of Infrastructure as Code.

## 4.2. Policy Definitions

The policies are organized modularly, with a main policy.sentinel file importing and orchestrating individual policy checks.

### 4.2.1. `policy.sentinel`

This is the main entry point for Sentinel evaluation. It imports all specific policy files and defines parameters that can be passed to them (e.g., `project_prefix`, `allowed_locations`).

### 4.2.2. `aws-s3-bucket-security.sentinel`

This policy ensures that all S3 buckets created within the project scope adhere to fundamental security best practices:

- **Private ACLs:** All buckets must have an Access Control List (ACL) set to `private`.
- **Server-Side Encryption:** All buckets must have server-side encryption enabled (e.g., AES256 or KMS).
- **Versioning Enabled:** All buckets must have versioning enabled for data recovery and protection against accidental deletion.
- **Block Public Access Settings:** All four Block Public Access settings (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`) must be set to `true` to prevent unintended public exposure.

### 4.2.3. `aws-iam-role-least-privilege.sentinel`

This policy enforces the principle of least privilege for IAM roles created within the project:

- **No Universal Assume Role:** Prevents IAM roles from having an `assume_role_policy` that allows `sts:AssumeRole` from `*` (any principal).
- **No Wildcard Resource and Action:** Disallows IAM policies (inline or attached) that grant `Allow` effect with `Resource: "*"` and `Action: "*"`.
- **No Wildcard Action (Unless Service Role):** Prevents policies from having `Allow` effect with `Action: "*"` unless it's for a specific, justified AWS service role (e.g., AWS Glue, SageMaker service roles that require broader permissions for their operation).

### 4.2.4. `aws-sagemaker-endpoint-security.sentinel`

This policy ensures that Amazon SageMaker endpoints are deployed securely and efficiently:

- **Allowed Instance Types:** Restricts SageMaker inference endpoint instance types to a predefined list (e.g., `ml.t2.medium`, `ml.m5.large`) to control costs and standardize deployments.
- **KMS Encryption for Volumes:** Requires SageMaker endpoint data volumes to be encrypted using a KMS key (either AWS-managed or customer-managed).

### 4.2.5. `aws-lambda-security.sentinel`

This policy enforces secure configurations for AWS Lambda functions:

- **Allowed Runtime:** Ensures Lambda functions use a specific, approved runtime (e.g., `python3.9`) for consistency and security patching.
- **Memory Size Limits:** Enforces a maximum memory size to prevent excessive resource consumption.
- **Timeout Limits:** Sets a maximum timeout to prevent long-running or runaway functions.
- **Code from S3:** Requires Lambda function code to be deployed from an S3 bucket (rather than inline or direct upload), which is a best practice for versioning and CI/CD.
- **Dead Letter Queue (DLQ) Configuration:** Requires Lambda functions to be configured with a Dead Letter Queue (DLQ) for asynchronous invocations, ensuring failed events are captured for debugging and reprocessing.

### 4.2.6. `aws-cloudfront-https-only.sentinel`

This policy ensures that CloudFront distributions enforce secure communication:

- **HTTPS Only:** Requires CloudFront distributions to use `https-only` or `redirect-to-https` for their viewer protocol policy, ensuring all traffic between viewers and CloudFront is encrypted.

### 4.2.7. `aws-glue-job-security.sentinel`

This policy enforces secure configurations for AWS Glue jobs:

- **Allowed Worker Types:** Restricts Glue jobs to use a predefined list of allowed worker types (e.g., `Standard`, `G.1X`, `G.2X`) for cost control and performance standardization.
- **Encryption Enabled:** Checks for the presence of a security configuration for Glue jobs, implying encryption for data in transit and at rest during job execution.

### 4.2.8. `aws-sns-topic-encryption.sentinel`

This policy ensures that Amazon SNS topics are encrypted at rest:

- **KMS Encryption:** Requires SNS topics to have a kms_master_key_id configured, ensuring messages stored in the topic are encrypted using AWS KMS.

These policies collectively form a strong governance framework, ensuring that **AWS Egress Cost Optimizer** solution is deployed securely and adheres to the organization's compliance requirements.

