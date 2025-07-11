# Glue ETL script to process AWS VPC Flow Logs
# This script processes VPC Flow Logs to identify egress traffic, aggregates it, and writes the results to S3 in Parquet format.
# It is designed to be run as an AWS

import sys
from awsglue.transforms import * # type: ignore
from awsglue.utils import getResolvedOptions # type: ignore
from pyspark import SparkContext
from awsglue.context import GlueContext # type: ignore
from awsglue.job import Job # type: ignore
from pyspark.sql.functions import col, lit, sum as spark_sum, from_unixtime, to_timestamp, hour, dayofmonth, month, year, concat_ws, expr, when, to_date

# Initialize Glue context
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'source_bucket',
    'target_bucket',
    'source_table', # Name of the Glue Data Catalog table for VPC Flow Logs
    'target_path'   # S3 path prefix within target_bucket for output
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

# --- Read VPC Flow Logs data from Glue Data Catalog ---
# VPC Flow Logs are typically partitioned by year, month, day, hour.
datasource = glueContext.create_dynamic_frame.from_catalog(
    database=GLUE_DATABASE,
    table_name=SOURCE_TABLE,
    transformation_ctx="datasource_flow_logs"
)

# Convert to Spark DataFrame
df_flow_logs = datasource.toDF()

# --- Pre-processing and Feature Extraction ---
# Filter for 'REJECT' (denied) and 'ACCEPT' (allowed) traffic
# Focus on egress traffic: where 'srcaddr' is an internal VPC IP and 'dstaddr' is external.
# This requires knowing your VPC CIDR ranges. For simplicity, we'll assume external IPs are not in private ranges.
# A more robust solution would involve looking up VPC CIDRs.

# Common private IP ranges (RFC 1918)
private_ip_ranges = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16"
]

# Function to check if IP is private (conceptual, would need UDF or more complex Spark logic)
# For simplicity, we'll assume traffic where srcaddr is private and dstaddr is public is egress.
# In a real scenario, you'd use a more robust IP range check.
# You might also need to join with EC2 instance metadata or ENI details to identify the specific resource.

df_flow_logs_filtered = df_flow_logs.filter(
    (col("action") == "ACCEPT") & # Only focus on accepted traffic
    (col("bytes") > 0) # Only consider flows with actual data transfer
)

# Identify potential egress traffic
# This is a simplified heuristic: if the destination IP is NOT a private IP, it's considered egress.
# This requires careful consideration of your network topology (e.g., VPNs, Direct Connect).
# A more accurate approach would involve checking if dstaddr is outside your known VPC CIDRs.
df_egress_flows = df_flow_logs_filtered.withColumn("is_egress",
    when(
        (col("dstaddr").substr(0, 3).isin("10.", "172", "192").isNull()) |
        (col("dstaddr").substr(0, 3).isin("172") & (col("dstaddr").substr(4, 2).cast("int") < 16 | col("dstaddr").substr(4, 2).cast("int") > 31)),
        lit(1)
    ).otherwise(lit(0))
).filter(col("is_egress") == 1)


# Extract relevant features and aggregate
df_aggregated_flows = df_egress_flows.groupBy(
        to_date(from_unixtime(col("start"))).alias("flow_date"), # Convert Unix timestamp to date
        hour(from_unixtime(col("start"))).alias("flow_hour"), # Hour of the day
        col("srcaddr").alias("source_ip"),
        col("dstaddr").alias("destination_ip"),
        col("dstport").alias("destination_port"),
        col("protocol").alias("protocol"),
        col("vpc_id").alias("vpc_id"),
        col("instance_id").alias("instance_id"), # If flow logs capture this
        col("interface_id").alias("network_interface_id") # If flow logs capture this
    ) \
    .agg(
        spark_sum(col("bytes")).alias("total_egress_bytes"),
        spark_sum(col("packets")).alias("total_egress_packets"),
        lit(1).alias("flow_count") # Count of unique flows
    ) \
    .orderBy("flow_date", "flow_hour", "total_egress_bytes")

# Add a processing timestamp
df_aggregated_flows = df_aggregated_flows.withColumn("processing_timestamp", from_unixtime(lit(job.started_on / 1000)))

# --- Write Processed Data to S3 (Parquet format) ---
# Partition by year, month, day, hour for efficient querying.
output_path = f"s3://{TARGET_BUCKET}/{TARGET_PATH}"
df_aggregated_flows.write \
    .mode("append") \
    .partitionBy(
        year(col("flow_date")),
        month(col("flow_date")),
        dayofmonth(col("flow_date")),
        col("flow_hour")
    ) \
    .parquet(output_path)

logger.info(f"Successfully processed VPC Flow Logs and wrote to {output_path}")

job.commit()