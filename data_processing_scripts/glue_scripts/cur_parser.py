# Glue ETL script to process AWS Cost and Usage Report (CUR) data
# This script filters for egress-related costs, aggregates them, and writes the results to S3 in Parquet format.
# It is designed to be run as an AWS Glue job.

import sys
from awsglue.transforms import *  # type: ignore
from awsglue.utils import getResolvedOptions  # type: ignore
from awsglue.context import GlueContext  # type: ignore
from awsglue.job import Job  # type: ignore
from pyspark import SparkContext
from pyspark.sql.functions import col, lit, sum as spark_sum, from_unixtime, to_date, date_format

# Initialize Glue context
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'source_bucket',
    'target_bucket',
    'source_table',  # Name of the Glue Data Catalog table for CUR
    'target_path'    # S3 path prefix within target_bucket for output
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
logger = spark._jvm.org.apache.log4j.LogManager.getLogger(__name__)
job.init(args['JOB_NAME'], args)

# --- Configuration ---
SOURCE_BUCKET = args['source_bucket']
TARGET_BUCKET = args['target_bucket']
SOURCE_TABLE = args['source_table']
TARGET_PATH = args['target_path']
GLUE_DATABASE = "egress_cost_optimizer_raw_logs_db" # Matches Glue database name from Terraform

# --- Read CUR data from Glue Data Catalog ---
# The CUR data is typically partitioned by year, month, day.
# Ensure your Glue Crawler for CUR has correctly discovered the schema.
datasource = glueContext.create_dynamic_frame.from_catalog(
    database=GLUE_DATABASE,
    table_name=SOURCE_TABLE,
    transformation_ctx="datasource_cur"
)

# Convert to Spark DataFrame for easier manipulation
df_cur = datasource.toDF()

# --- Filter for Egress-related Costs ---
# Identify common usage types related to data transfer out (egress).
# This list might need to be expanded based on your specific AWS services and usage patterns.
# Common egress usage types include:
# - DataTransfer-Out-Bytes (general data transfer out)
# - EU-DataTransfer-Out-Bytes (EU-specific)
# - USW1-DataTransfer-Out-Bytes (Region-specific)
# - CloudFront-Bytes-Out (CloudFront egress)
# - S3-Bytes-Out (S3 egress)
# - EC2-Instances-DataTransfer-Out-Bytes (EC2 egress)
# - RDS-DataTransfer-Out-Bytes (RDS egress)
# - VPN-DataTransfer-Out-Bytes (VPN egress)

egress_usage_types = [
    "DataTransfer-Out-Bytes",
    "CloudFront-Bytes-Out",
    "S3-Bytes-Out",
    "EC2-Instances-DataTransfer-Out-Bytes",
    "RDS-DataTransfer-Out-Bytes",
    "VPN-DataTransfer-Out-Bytes",
    "DataTransfer-Out-Bytes (Internet)", # Specific for some services
    "DataTransfer-Out-Bytes (Region-to-Region)", # Cross-region transfer
    "DataTransfer-Out-Bytes (Inter-Region)", # Inter-Region transfer
    "DataTransfer-Out-Bytes (AZ-to-AZ)" # Inter-AZ transfer
]

# Filter for egress-related line items and sum up the unblended cost
df_egress = df_cur.filter(col("line_item_usage_type").isin(egress_usage_types)) \
                 .withColumn("egress_cost", col("line_item_unblended_cost").cast("double"))

# --- Aggregate Egress Costs ---
# Aggregate by daily, service, and usage type for granular analysis.
# You can add more grouping keys like 'resource_tags_user_application', 'line_item_resource_id'
# if these fields are present and relevant in your CUR.

df_aggregated_egress = df_egress.groupBy(
        to_date(col("line_item_usage_start_date")).alias("usage_date"),
        col("product_servicecode").alias("service_code"),
        col("line_item_usage_type").alias("usage_type"),
        col("product_region").alias("region"),
        col("line_item_resource_id").alias("resource_id") # Include resource ID for drill-down
    ) \
    .agg(
        spark_sum(col("egress_cost")).alias("daily_egress_cost_usd"),
        spark_sum(col("line_item_usage_amount").cast("double")).alias("daily_egress_usage_amount")
    ) \
    .orderBy("usage_date", "service_code", "usage_type")

# Add a processing timestamp
df_aggregated_egress = df_aggregated_egress.withColumn("processing_timestamp", from_unixtime(lit(job.started_on / 1000)))

# --- Write Processed Data to S3 (Parquet format for efficiency) ---
# Partition by year, month, day for efficient querying in Athena/SageMaker.
output_path = f"s3://{TARGET_BUCKET}/{TARGET_PATH}"
df_aggregated_egress.write \
    .mode("append") \
    .partitionBy("usage_date") \
    .parquet(output_path)

logger.info(f"Successfully processed CUR data and wrote to {output_path}")

job.commit()
