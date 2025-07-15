# 6. Data Processing Scripts (Glue & SageMaker)

This section details the Python scripts responsible for the Extract, Transform, Load (ETL) processes and feature engineering. These scripts transform raw log data into a clean, structured, and feature-rich format suitable for machine learning models and analytical dashboards.

## 6.1. Overview

The data processing pipeline is designed to:

1. **Ingest Raw Data:** Read raw log files (CUR, VPC Flow Logs) from the S3 Raw Logs Bucket.
2. **Clean & Standardize:** Parse raw data, handle missing values, and standardize formats.
3. **Aggregate:** Consolidate granular data into meaningful time windows (e.g., daily, hourly aggregates).
4. **Extract Features:** Derive new features relevant for anomaly detection (e.g., time-based features, ratios).
5. **Store Processed Data:** Write the transformed data to the S3 Processed Data Bucket in an optimized format (Parquet).

## 6.2. AWS Glue Scripts (`glue_scripts/`)

These Python scripts are designed to run as AWS Glue ETL Jobs. They leverage Apache Spark within the Glue environment for scalable data processing.

### 6.2.1. `cur_parser.py`

- **Purpose:** Parses AWS Cost and Usage Reports (CUR) to extract and aggregate egress-related costs.
- **Input:** Reads raw CUR data from the Glue Data Catalog table (which is populated by the `cur_crawler`).
- **Key Actions:**

    - Filters CUR line items to include only known data transfer out (egress) usage types (e.g., `DataTransfer-Out-Bytes`, `CloudFront-Bytes-Out`, `S3-Bytes-Out`).
    - Aggregates egress costs and usage amounts by `usage_date`, `service_code`, `usage_type`, `region`, and `resource_id`.
    - Adds a `processing_timestamp` for tracking.

- **Output:** Writes the aggregated egress cost data to the S3 Processed Data Bucket in Parquet format, partitioned by `usage_date`.
- **Glue Job Configuration:** Configured as an AWS Glue ETL Job with specified worker type and number of workers. Uses job bookmarking for incremental processing.

### 6.2.2. `flow_log_aggregator.py`

- **Purpose:** Processes VPC Flow Logs to identify and aggregate egress traffic patterns.
- **Input:** Reads raw VPC Flow Log data from the Glue Data Catalog table (populated by the `vpc_flow_logs_crawler`).
- **Key Actions:**

    - Filters for accepted traffic with actual byte transfer.
    - Identifies potential egress traffic based on destination IP addresses (e.g., if destination is outside common private IP ranges). Note: This is a simplified heuristic; a robust solution might require dynamic VPC CIDR lookups.
    - Aggregates flow data by `flow_date`, `flow_hour`, `source_ip`, `destination_ip`, `destination_port`, `protocol`, `vpc_id`, `instance_id`, and `network_interface_id`.
    - Calculates `total_egress_bytes`, `total_egress_packets`, and `flow_count`.
    - Adds a processing_timestamp.

- **Output:** Writes the aggregated flow data to the S3 Processed Data Bucket in Parquet format, partitioned by year, month, day, and hour.
- **Glue Job Configuration:** Configured as an AWS Glue ETL Job with specified worker type and number of workers. Uses job bookmarking for incremental processing.

## 6.3. SageMaker Processing Scripts (`sagemaker_processing_scripts/`)

These Python scripts are designed to run as Amazon SageMaker Processing Jobs, performing more advanced data transformations and feature engineering, often combining outputs from multiple Glue jobs.

### 6.3.1. `feature_engineering.py`

- **Purpose:** Performs advanced feature engineering on the combined and aggregated egress data, preparing it for the ML anomaly detection model.
- **Input:** Reads processed data (e.g., aggregated egress costs from `cur_parser.py` and aggregated flow data from `flow_log_aggregator`.py) from the S3 Processed Data Bucket.
- **Key Actions:**

    - **Time-based Features:** Extracts features like `day_of_week`, `day_of_month`, `month`, `week_of_year`, and `is_weekend` from date columns.
    - **Lag Features (Conceptual):** Placeholder for creating features based on historical data (e.g., egress from previous day/week, rolling averages). This requires careful sorting and grouping.
    - **Ratio Features (Conceptual):** Placeholder for creating features like egress bytes per total bytes in a region.
    - **Categorical Encoding:** Uses `sklearn.preprocessing.OneHotEncoder` to convert categorical features (e.g., `service_code`, `region`, `usage_type`) into numerical representations.
    - **Numerical Scaling:** Uses `sklearn.preprocessing.StandardScaler` to scale numerical features (e.g., `daily_egress_cost_usd`, `daily_egress_usage_amount`), which is essential for many ML algorithms.
    - Handles sparse matrix output from `ColumnTransformer` by converting it to a dense array.

- **Output:** Writes the final feature-engineered dataset to the S3 Processed Data Bucket in Parquet format.
- **Artifacts:** Optionally saves the `preprocessor` object (`preprocessor.joblib`) to S3, which can be reused by the inference pipeline to ensure consistent data transformation.
- **SageMaker Processing Job Configuration:** This script is designed to be executed by a SageMaker Processing Job, which provides managed compute resources for large-scale data transformation.

These data processing scripts are the backbone of the solution, ensuring that the raw, voluminous log data is transformed into a clean, insightful, and machine-learning-ready format.


