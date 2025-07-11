import argparse
import boto3
import os
import random
import datetime
import pandas as pd
import logging
import io
from botocore.exceptions import ClientError

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def generate_cur_egress_data(num_records, start_date, project_name):
    """
    Generates synthetic AWS Cost and Usage Report (CUR) data for egress.
    This is a simplified representation of CUR.
    """
    data = []
    services = ["Amazon Elastic Compute Cloud", "Amazon S3", "Amazon CloudFront", "Amazon RDS"]
    usage_types = ["DataTransfer-Out-Bytes", "CloudFront-Bytes-Out", "S3-Bytes-Out"]
    regions = ["us-east-1", "us-west-2", "eu-central-1"]
    
    for _ in range(num_records):
        date = start_date + datetime.timedelta(days=random.randint(0, 29)) # Data for 30 days
        service = random.choice(services)
        usage_type = random.choice(usage_types)
        region = random.choice(regions)
        
        # Simulate normal daily egress cost (e.g., $0.05 to $5)
        cost = round(random.uniform(0.05, 5.0), 4)
        # Simulate usage amount in bytes (e.g., 1MB to 100MB)
        usage_amount = random.randint(1024 * 1024, 100 * 1024 * 1024) 
        
        # Introduce a spike for a specific service/day to simulate anomaly
        if random.random() < 0.05: # 5% chance of an anomaly
            cost *= random.uniform(5, 20) # 5x to 20x spike
            usage_amount *= random.randint(5, 20)
            logger.info(f"Simulating anomaly: {service} on {date.strftime('%Y-%m-%d')} with cost {cost:.2f}")

        data.append({
            "line_item_usage_start_date": date.strftime('%Y-%m-%d %H:%M:%S'),
            "line_item_usage_end_date": (date + datetime.timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S'),
            "line_item_usage_type": usage_type,
            "line_item_unblended_cost": cost,
            "line_item_usage_amount": usage_amount,
            "product_servicecode": service.replace("Amazon ", ""),
            "product_region": region,
            "line_item_resource_id": f"arn:aws:{service.lower().replace('amazon ', '').replace(' ', '')}:{region}:123456789012:resource-{random.randint(1000,9999)}"
        })
    
    df = pd.DataFrame(data)
    return df

def generate_flow_log_data(num_records, start_time, vpc_id, project_name):
    """
    Generates synthetic VPC Flow Log data.
    """
    data = []
    internal_ips = [f"10.0.{random.randint(0,255)}.{random.randint(0,255)}" for _ in range(10)]
    external_ips = [f"{random.randint(1,254)}.{random.randint(0,254)}.{random.randint(1,254)}.{random.randint(1,254)}" for _ in range(10)]
    
    for _ in range(num_records):
        timestamp = int(start_time.timestamp()) + random.randint(0, 3599) # Within an hour
        src_ip = random.choice(internal_ips)
        dst_ip = random.choice(external_ips)
        bytes_transferred = random.randint(1000, 1000000) # 1KB to 1MB
        packets = random.randint(10, 1000)
        dst_port = random.choice([80, 443, 8080, 22, 53])
        protocol = random.choice([6, 17]) # TCP, UDP
        action = "ACCEPT"
        
        # Simulate egress spike
        if random.random() < 0.02: # 2% chance of a large flow
            bytes_transferred *= random.randint(5, 50)
            packets *= random.randint(5, 50)
            logger.info(f"Simulating large flow: {bytes_transferred} bytes from {src_ip} to {dst_ip}:{dst_port}")

        data.append({
            "version": 2,
            "account_id": "123456789012", # Dummy account ID
            "interface_id": f"eni-{random.randint(10000000,99999999)}",
            "srcaddr": src_ip,
            "dstaddr": dst_ip,
            "srcport": random.randint(1024, 65535),
            "dstport": dst_port,
            "protocol": protocol,
            "bytes": bytes_transferred,
            "packets": packets,
            "start": timestamp,
            "end": timestamp + random.randint(10, 600),
            "action": action,
            "log_status": "OK",
            "vpc_id": vpc_id,
            "subnet_id": f"subnet-{random.randint(10000000,99999999)}",
            "instance_id": f"i-{random.randint(10000000,99999999)}",
            "tcp_flags": random.randint(0, 255),
            "type": "IPv4",
            "pkt_srcaddr": src_ip,
            "pkt_dstaddr": dst_ip,
            "region": "us-east-1" # Dummy region
        })
    
    df = pd.DataFrame(data)
    return df

def upload_dataframe_to_s3(df, bucket_name, key_prefix, file_name):
    """Uploads a Pandas DataFrame to S3 as a Parquet file."""
    s3 = boto3.client('s3')
    full_key = f"{key_prefix}{file_name}"
    
    try:
        # Save DataFrame to a buffer as Parquet
        parquet_buffer = io.BytesIO()
        df.to_parquet(parquet_buffer, index=False)
        parquet_buffer.seek(0) # Rewind to the beginning of the buffer

        s3.put_object(Bucket=bucket_name, Key=full_key, Body=parquet_buffer.getvalue())
        logger.info(f"Successfully uploaded {len(df)} records to s3://{bucket_name}/{full_key}")
    except ClientError as e:
        logger.error(f"Failed to upload data to S3: {e}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during S3 upload: {e}", exc_info=True)
        raise

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simulate AWS egress data and upload to S3.")
    parser.add_argument("--bucket-name", required=True, help="Name of the S3 bucket for raw logs.")
    parser.add_argument("--data-type", choices=["cur", "flow_logs"], required=True, help="Type of data to simulate: 'cur' or 'flow_logs'.")
    parser.add_argument("--num-records", type=int, default=1000, help="Number of records to generate.")
    parser.add_argument("--start-date", type=str, default=datetime.date.today().strftime('%Y-%m-%d'), help="Start date for data generation (YYYY-MM-DD).")
    parser.add_argument("--vpc-id", type=str, help="VPC ID for flow logs simulation (required for flow_logs data_type).")
    parser.add_argument("--project-name", type=str, default="egress-cost-optimizer", help="Project name for naming conventions.")

    args = parser.parse_args()

    start_date_obj = datetime.datetime.strptime(args.start_date, '%Y-%m-%d').date()

    if args.data_type == "cur":
        logger.info(f"Generating {args.num_records} synthetic CUR egress data records...")
        df_simulated = generate_cur_egress_data(args.num_records, start_date_obj, args.project_name)
        # CUR reports are typically delivered with a specific path structure
        # e.g., <report-prefix>/<report-name>/YYYYMMDD-YYYYMMDD/<hash>/<file>.csv.gz
        # For simulation, we'll simplify to a daily parquet file.
        cur_report_date_prefix = (start_date_obj + datetime.timedelta(days=random.randint(0,29))).strftime('%Y%m%d') # Pick a random day within range
        s3_key_prefix = f"egress-cur/{args.project_name}-report/{cur_report_date_prefix}-{cur_report_date_prefix}/dummyhash/" # Matches typical CUR path structure
        file_name = f"egress_cost_data_{cur_report_date_prefix}.parquet"
        upload_dataframe_to_s3(df_simulated, args.bucket_name, s3_key_prefix, file_name)
        logger.info("CUR data simulation complete.")

    elif args.data_type == "flow_logs":
        if not args.vpc_id:
            parser.error("--vpc-id is required for 'flow_logs' data_type.")
        logger.info(f"Generating {args.num_records} synthetic VPC Flow Log data records for VPC {args.vpc_id}...")
        df_simulated = generate_flow_log_data(args.num_records, datetime.datetime.combine(start_date_obj, datetime.time.min), args.vpc_id, args.project_name)
        
        # Flow logs are typically delivered to S3 in hourly partitions
        # e.g., vpc_flow_logs/AWSLogs/account_id/vpcflowlogs/region/YYYY/MM/DD/
        log_date = (start_date_obj + datetime.timedelta(days=random.randint(0,29))) # Pick a random day
        log_hour = random.randint(0,23) # Pick a random hour
        s3_key_prefix = f"vpc_flow_logs/AWSLogs/123456789012/vpcflowlogs/{os.environ.get('AWS_REGION', 'us-east-1')}/{log_date.strftime('%Y/%m/%d')}/"
        file_name = f"flow_logs_{log_date.strftime('%Y%m%d')}_{log_hour:02d}.parquet"
        upload_dataframe_to_s3(df_simulated, args.bucket_name, s3_key_prefix, file_name)
        logger.info("VPC Flow Log data simulation complete.")

    logger.info("Script finished.")