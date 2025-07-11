# This code is part of a larger application that uses AWS services to analyze egress cost anomalies using 
# Amazon Bedrock and other AWS services. It gathers contextual data, invokes a Large Language Model (LLM) 
# for root cause analysis, and publishes enriched alerts to an SNS topic.
# The code is designed to run as an AWS Lambda function, triggered by AWS Step Functions, and it integrates with 
# AWS Config, CloudTrail, Cost Explorer, and Amazon Bedrock for comprehensive analysis and alerting.

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
bedrock_runtime = boto3.client('bedrock-runtime')
config_client = boto3.client('config')
cloudtrail_client = boto3.client('cloudtrail')
ce_client = boto3.client('ce') # Cost Explorer client
s3_client = boto3.client('s3') # To read prompt templates

# Environment variables
BEDROCK_MODEL_ID = os.environ.get('BEDROCK_MODEL_ID')
SNS_ANOMALY_TOPIC_ARN = os.environ.get('SNS_ANOMALY_TOPIC_ARN')
PROCESSED_DATA_BUCKET = os.environ.get('PROCESSED_DATA_BUCKET') # For fetching more data if needed
PROMPT_TEMPLATE_KEY = "bedrock_prompts/egress_root_cause_prompt.txt" # Adjust path to your prompt template

def get_contextual_data(resource_id: str, anomaly_details: dict) -> str:
    """
    Gathers relevant contextual data from AWS Config, CloudTrail, and Cost Explorer.
    """
    context_data = []

    # --- 1. AWS Config: Recent resource changes ---
    try:
        # Get resource configuration history for the last 24 hours
        # This is a simplified lookup. For cross-account, you'd need assume-role.
        logger.info(f"Querying AWS Config for resource: {resource_id}")
        config_response = config_client.get_resource_config_history(
            resourceType='AWS::EC2::Instance', # Example: Adjust based on resource type
            resourceId=resource_id,
            laterTime=anomaly_details.get('timestamp', str(pd.Timestamp.now() - pd.Timedelta(days=1))), # Look back 24 hours from anomaly
            limit=5 # Get latest 5 changes
        )
        if config_response.get('configurationItems'):
            context_data.append("--- AWS Config Recent Changes ---")
            for item in config_response['configurationItems']:
                context_data.append(f"Timestamp: {item['configurationItemCaptureTime']}, ChangeType: {item['changeType']}, Status: {item['configurationItemStatus']}")
                # You might parse item['configuration'] for more details
            context_data.append("")
    except ClientError as e:
        logger.warning(f"Could not retrieve Config history for {resource_id}: {e}")

    # --- 2. AWS CloudTrail: Recent API calls ---
    try:
        # Look up CloudTrail events related to the resource or service in the last 24 hours
        logger.info(f"Querying AWS CloudTrail for resource: {resource_id}")
        cloudtrail_response = cloudtrail_client.lookup_events(
            LookupAttributes=[
                {'AttributeKey': 'ResourceName', 'AttributeValue': resource_id.split('/')[-1]}, # Use resource name
                {'AttributeKey': 'ResourceType', 'AttributeValue': resource_id.split('/')[6]} # Example: 'AWS::EC2::Instance'
            ],
            StartTime=pd.Timestamp(anomaly_details.get('timestamp', pd.Timestamp.now())) - pd.Timedelta(days=1),
            EndTime=pd.Timestamp(anomaly_details.get('timestamp', pd.Timestamp.now()))
        )
        if cloudtrail_response.get('Events'):
            context_data.append("--- AWS CloudTrail Recent Events ---")
            for event in cloudtrail_response['Events'][:5]: # Limit to 5 events
                context_data.append(f"EventTime: {event['EventTime']}, EventName: {event['EventName']}, User: {event['Username']}")
            context_data.append("")
    except ClientError as e:
        logger.warning(f"Could not retrieve CloudTrail events for {resource_id}: {e}")

    # --- 3. AWS Cost Explorer (for broader cost context) ---
    try:
        # Get cost breakdown for the service/resource around the anomaly time
        logger.info(f"Querying AWS Cost Explorer for service: {anomaly_details.get('service_code')}")
        ce_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': (pd.Timestamp(anomaly_details.get('timestamp', pd.Timestamp.now())) - pd.Timedelta(days=2)).strftime('%Y-%m-%d'),
                'End': (pd.Timestamp(anomaly_details.get('timestamp', pd.Timestamp.now())) + pd.Timedelta(days=1)).strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'USAGE_TYPE'} # To see egress usage types
            ]
        )
        if ce_response.get('ResultsByTime'):
            context_data.append("--- AWS Cost Explorer Snapshot ---")
            for result in ce_response['ResultsByTime']:
                context_data.append(f"Date: {result['TimePeriod']['Start']}, Total Cost: {result['Total']['BlendedCost']['Amount']} {result['Total']['BlendedCost']['Unit']}")
                # You can parse Groups for more detail on services/usage types
            context_data.append("")
    except ClientError as e:
        logger.warning(f"Could not retrieve Cost Explorer data: {e}")

    # --- 4. Raw Log Snippets (Conceptual) ---
    # In a more advanced setup, you might fetch relevant log lines directly from S3
    # (VPC Flow Logs, S3 Access Logs) around the anomaly timestamp.
    # This would require more complex S3 object listing/filtering.
    # context_data.append("--- Raw Log Snippets (Conceptual) ---")
    # context_data.append("Relevant lines from VPC Flow Logs or S3 Access Logs around anomaly timestamp.")
    # context_data.append("")

    return "\n".join(context_data)

def load_prompt_template(bucket_name: str, key: str) -> str:
    """Loads the prompt template from S3."""
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=key)
        return response['Body'].read().decode('utf-8')
    except ClientError as e:
        logger.error(f"Failed to load prompt template from s3://{bucket_name}/{key}: {e}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred loading prompt template: {e}")
        raise

def invoke_bedrock_llm(model_id: str, prompt: str) -> str:
    """
    Invokes a Large Language Model (LLM) via Amazon Bedrock.
    """
    body = json.dumps({
        "prompt": f"\n\nHuman: {prompt}\n\nAssistant:",
        "max_tokens_to_sample": 1000, # Adjust as needed
        "temperature": 0.1,
        "top_p": 0.9
    })

    try:
        response = bedrock_runtime.invoke_model(
            modelId=model_id,
            contentType="application/json",
            accept="application/json",
            body=body
        )
        response_body = json.loads(response.get('body').read())
        return response_body.get('completion')
    except ClientError as e:
        logger.error(f"Bedrock invocation failed: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during Bedrock invocation: {e}", exc_info=True)
        raise

def publish_enriched_alert(subject: str, message: str):
    """
    Publishes an enriched alert message to the SNS topic.
    """
    sns = boto3.client('sns')
    try:
        sns.publish(
            TopicArn=SNS_ANOMALY_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        logger.info(f"Published enriched alert to SNS topic: {SNS_ANOMALY_TOPIC_ARN}")
    except ClientError as e:
        logger.error(f"Failed to publish SNS message: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during SNS publish: {e}", exc_info=True)
        raise

def lambda_handler(event, context):
    """
    Lambda handler function for Bedrock Analyzer.
    Triggered by AWS Step Functions.
    """
    logger.info(f"Received event from Step Functions: {json.dumps(event)}")

    # Check and assert all environment variables are set
    if not all([BEDROCK_MODEL_ID, SNS_ANOMALY_TOPIC_ARN, PROCESSED_DATA_BUCKET]):
        logger.error("Missing one or more required environment variables. Please check configuration.")
        return {
            'statusCode': 500,
            'body': json.dumps('Configuration error: Missing environment variables.')
        }

    # Help type-checkers: these cannot be None beyond this point
    assert BEDROCK_MODEL_ID is not None
    assert SNS_ANOMALY_TOPIC_ARN is not None
    assert PROCESSED_DATA_BUCKET is not None

    # Assign defaults before try-block so they're always available
    resource_id = event.get('resourceId', 'N/A')
    anomaly_type = event.get('anomalyType', 'EgressCostSpike')
    cost_impact = event.get('costImpact', 'N/A')
    anomaly_details = event.get('details', {})

    try:
        logger.info(f"Analyzing anomaly: Type={anomaly_type}, Resource={resource_id}, Cost={cost_impact}")

        # 1. Load Prompt Template
        prompt_template = load_prompt_template(PROCESSED_DATA_BUCKET, PROMPT_TEMPLATE_KEY)
        if not prompt_template:
            raise Exception("Failed to load Bedrock prompt template.")

        # 2. Gather Contextual Data
        context_data = get_contextual_data(resource_id, anomaly_details)
        if not context_data:
            logger.warning(f"No additional context found for {resource_id}. Proceeding with limited context.")

        # 3. Construct the Full Prompt
        full_prompt = prompt_template.format(
            anomaly_type=anomaly_type,
            resource_id=resource_id,
            cost_impact=cost_impact,
            anomaly_details=json.dumps(anomaly_details, indent=2),
            context_data=context_data
        )
        logger.info(f"Full prompt for Bedrock (first 500 chars): {full_prompt[:500]}...")

        # 4. Invoke Bedrock LLM
        llm_response_text = invoke_bedrock_llm(BEDROCK_MODEL_ID, full_prompt)
        logger.info(f"Bedrock LLM response (first 500 chars): {llm_response_text[:500]}...")

        # 5. Publish Enriched Alert
        subject = f"Egress Anomaly Detected: {anomaly_type} on {resource_id}"
        message = f"An egress cost anomaly has been detected.\n\n" \
                  f"Anomaly Type: {anomaly_type}\n" \
                  f"Resource ID: {resource_id}\n" \
                  f"Cost Impact: ${cost_impact}\n\n" \
                  f"--- AI-Powered Root Cause Analysis & Recommendations ---\n" \
                  f"{llm_response_text}\n\n" \
                  f"--- Raw Anomaly Details ---\n" \
                  f"{json.dumps(anomaly_details, indent=2)}"

        publish_enriched_alert(subject, message)

        return {
            'statusCode': 200,
            'body': json.dumps('Bedrock analysis completed and alert sent.'),
            'llm_analysis': llm_response_text # Return LLM analysis for Step Function to use
        }

    except Exception as e:
        logger.error(f"An unhandled error occurred in Bedrock Analyzer: {e}", exc_info=True)
        # Publish a failure alert
        publish_enriched_alert(
            subject=f"CRITICAL: Bedrock Analyzer Failed for {resource_id}",
            message=f"Bedrock analysis failed for anomaly on resource {resource_id} (Type: {anomaly_type}). Error: {e}\nFull event: {json.dumps(event)}"
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'Internal Server Error: {e}')
        }