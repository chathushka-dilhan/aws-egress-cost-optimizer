# Lambda function to trigger SageMaker endpoint for egress cost anomaly detection
# This function is triggered by EventBridge (e.g., hourly) to fetch the latest processed
# data, invoke the SageMaker endpoint for anomaly detection, and trigger a Step Function
# for remediation if anomalies are detected.


import json
import os
import logging
import boto3
import pandas as pd
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# AWS SDK clients
sagemaker_runtime = boto3.client('sagemaker-runtime')
s3 = boto3.client('s3')
stepfunctions = boto3.client('stepfunctions')

# Environment variables
SAGEMAKER_ENDPOINT_NAME = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
PROCESSED_DATA_BUCKET = os.environ.get('PROCESSED_DATA_BUCKET')
SNS_ANOMALY_TOPIC_ARN = os.environ.get('SNS_ANOMALY_TOPIC_ARN')
STEP_FUNCTION_ARN = os.environ.get('STEP_FUNCTION_ARN') # ARN of the egress remediation Step Function

def lambda_handler(event, context):
    """
    Lambda handler function.
    Triggered by EventBridge (e.g., hourly).
    Fetches latest processed data, invokes SageMaker endpoint, and triggers Step Function on anomaly.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    if not all([SAGEMAKER_ENDPOINT_NAME, PROCESSED_DATA_BUCKET, SNS_ANOMALY_TOPIC_ARN, STEP_FUNCTION_ARN]):
        logger.error("Missing one or more required environment variables. Please check configuration.")
        return {
            'statusCode': 500,
            'body': json.dumps('Configuration error: Missing environment variables.')
        }

    try:
        # --- 1. Fetch Latest Processed Data ---
        # This is a simplified example. In a real scenario, you'd fetch the latest
        # processed features (e.g., hourly/daily aggregates) from S3.
        # You might need to list objects by prefix and get the latest one.
        # For demonstration, let's assume a fixed path for the latest data.
        latest_data_key = "processed_egress_costs/processed_features/latest_features.parquet" # Adjust this path
        logger.info(f"Fetching latest processed data from s3://{PROCESSED_DATA_BUCKET}/{latest_data_key}")

        try:
            response = s3.get_object(Bucket=PROCESSED_DATA_BUCKET, Key=latest_data_key)
            df_latest_features = pd.read_parquet(io.BytesIO(response['Body'].read()))
            logger.info(f"Successfully loaded {len(df_latest_features)} data points for inference.")
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                logger.warning(f"No latest features file found at {latest_data_key}. Skipping inference.")
                return {
                    'statusCode': 200,
                    'body': json.dumps('No new data for inference.')
                }
            else:
                raise e # Re-raise other S3 client errors
        except Exception as e:
            logger.error(f"Error loading processed features: {e}")
            raise

        # Prepare data for SageMaker endpoint invocation
        # The inference_script.py expects JSON format
        inference_payload = df_latest_features.to_json(orient='records')
        logger.info(f"Prepared inference payload (first 100 chars): {inference_payload[:100]}...")

        # --- 2. Invoke SageMaker Endpoint for Anomaly Detection ---
        logger.info(f"Invoking SageMaker endpoint: {SAGEMAKER_ENDPOINT_NAME}")
        sagemaker_response = sagemaker_runtime.invoke_endpoint(
            EndpointName=SAGEMAKER_ENDPOINT_NAME,
            ContentType='application/json',
            Accept='application/json',
            Body=inference_payload
        )

        # Parse SageMaker response
        result = json.loads(sagemaker_response['Body'].read().decode('utf-8'))
        df_inference_results = pd.DataFrame(result)
        logger.info(f"SageMaker inference returned {len(df_inference_results)} results.")
        logger.info(f"Inference results head:\n{df_inference_results.head()}")

        # --- 3. Identify Anomalies and Trigger Step Function ---
        anomalies = df_inference_results[df_inference_results['is_anomaly'] == 1]

        if not anomalies.empty:
            logger.warning(f"Detected {len(anomalies)} egress cost anomalies!")
            for index, anomaly in anomalies.iterrows():
                # Prepare input for Step Function
                # This input should contain enough context for Bedrock Analyzer and Remediation Orchestrator
                step_function_input = {
                    "anomalyType": "EgressCostSpike", # Generic type, Bedrock will refine
                    "resourceId": anomaly.get('resource_id', 'unknown'), # Assuming 'resource_id' is in processed features
                    "costImpact": anomaly.get('daily_egress_cost_usd', 0),
                    "anomalyScore": anomaly.get('anomaly_score', 0),
                    "timestamp": anomaly.get('usage_date', str(pd.Timestamp.now())),
                    "details": anomaly.to_dict() # Pass full anomaly details
                }
                logger.info(f"Triggering Step Function with input: {json.dumps(step_function_input)}")

                # Start Step Function execution
                stepfunctions.start_execution(
                    stateMachineArn=STEP_FUNCTION_ARN,
                    input=json.dumps(step_function_input)
                )
                logger.info("Step Function execution started for anomaly.")
        else:
            logger.info("No egress cost anomalies detected.")

        return {
            'statusCode': 200,
            'body': json.dumps('Anomaly detection process completed.')
        }

    except ClientError as e:
        logger.error(f"AWS Client Error: {e.response['Error']['Code']} - {e.response['Error']['Message']}", exc_info=True)
        # Publish to SNS for critical errors
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=SNS_ANOMALY_TOPIC_ARN,
            Subject=f"CRITICAL: Egress Anomaly Detector Trigger Failed in {context.function_name}",
            Message=f"An AWS client error occurred: {e.response['Error']['Message']}\nFunction ARN: {context.invoked_function_arn}"
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'AWS Client Error: {e.response["Error"]["Message"]}')
        }
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}", exc_info=True)
        # Publish to SNS for critical errors
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=SNS_ANOMALY_TOPIC_ARN,
            Subject=f"CRITICAL: Egress Anomaly Detector Trigger Failed in {context.function_name}",
            Message=f"An unexpected error occurred: {e}\nFunction ARN: {context.invoked_function_arn}"
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'Internal Server Error: {e}')
        }