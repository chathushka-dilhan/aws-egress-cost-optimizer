# 8. Utility Scripts

This section details auxiliary shell and Python scripts located in the `scripts/` directory. These scripts are not part of the core Terraform deployment or application logic but serve as helpful utilities for initial setup, data simulation, or prerequisites that might involve manual steps or data generation.

## 8.1. Overview

The utility scripts are designed to:

- Guide users through manual prerequisites that cannot be fully automated via Infrastructure as Code (e.g., AWS account-level settings).
- Generate synthetic data for testing the data ingestion, processing, and ML pipeline without relying on live traffic.

## 8.2. `setup_aws_billing_prerequisites.sh`

- **Purpose:** A shell script that guides the user through enabling AWS Cost and Usage Reports (CUR) and setting up an Amazon QuickSight user. These are crucial prerequisites for the solution's data sources and visualization capabilities.
- **Key Information Provided:**

    - Step-by-step instructions for enabling CUR in the AWS Billing console, emphasizing the importance of resource IDs and hourly granularity.
    - Guidance on configuring CUR to deliver reports to the S3 Raw Logs Bucket provisioned by Terraform.
    - Instructions for signing up for Amazon QuickSight and granting it necessary permissions to access S3 data via Athena/Glue Data Catalog.

- **Usage:** This script is intended to be run manually from the local machine to walk you through the console-based setup steps.

## 8.3. `simulate_egress_data.py`

- **Purpose:** A Python script to generate and upload synthetic egress data (simulating CUR and VPC Flow Logs) to your S3 Raw Logs Bucket. This is invaluable for testing the entire pipeline end-to-end without waiting for real traffic.
- **Key Features:**

    - **Data Type Selection:** Can generate either `cur` (Cost and Usage Report) or `flow_logs` (VPC Flow Logs) data.
    - **Record Generation:** Generates a specified number of synthetic records.
    - **Anomaly Simulation:** Randomly introduces "spikes" in egress costs or bytes transferred to simulate anomalies, allowing you to test your anomaly detection models.
    - **S3 Upload:** Uploads the generated data as Parquet files to the specified S3 bucket, mimicking the typical delivery paths for CUR and VPC Flow Logs.

- **Usage:**

    - Requires Python dependencies (`pandas`, `pyarrow`, `boto3`).
    - Run from the command line, specifying the S3 bucket name, data type, number of records, and an optional start date.
    - **Example for CUR data:**

        ```bash
        python scripts/simulate_egress_data.py --bucket-name <RAW_LOGS_S3_BUCKET_NAME> --data-type cur --num-records 5000
        ```

    - **Example for VPC Flow Logs data:**

        ```bash
        python scripts/simulate_egress_data.py --bucket-name <RAW_LOGS_S3_BUCKET_NAME> --data-type flow_logs --num-records 10000 --vpc-id <EXISTING_VPC_ID>
        ```

