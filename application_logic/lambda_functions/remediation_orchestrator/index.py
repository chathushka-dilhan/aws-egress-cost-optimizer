


import json
import os
import logging
import boto3
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# AWS SDK clients
s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')

# Environment variables
SNS_ANOMALY_TOPIC_ARN = os.environ.get('SNS_ANOMALY_TOPIC_ARN')

def remediate_s3_public_access(resource_id: str):
    """
    Remediates S3 bucket public access by blocking all public access settings.
    Resource ID format: arn:aws:s3:::bucket-name
    """
    bucket_name = resource_id.split(':::')[-1]
    logger.info(f"Attempting to remediate S3 public access for bucket: {bucket_name}")
    try:
        s3_client.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        logger.info(f"Successfully blocked all public access for S3 bucket: {bucket_name}")
        return {"status": "success", "message": f"Blocked public access for S3 bucket {bucket_name}."}
    except ClientError as e:
        logger.error(f"Failed to remediate S3 public access for {bucket_name}: {e}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during S3 remediation for {bucket_name}: {e}", exc_info=True)
        raise

def remediate_security_group(resource_id: str):
    """
    Remediates overly permissive security group rules (e.g., ingress 0.0.0.0/0 on all ports).
    Resource ID format: arn:aws:ec2:region:account-id:security-group/sg-xxxxxxxxxxxxxxxxx
    """
    sg_id = resource_id.split('/')[-1]
    logger.info(f"Attempting to remediate overly permissive rules for Security Group: {sg_id}")
    try:
        sg_details = ec2_client.describe_security_groups(GroupIds=[sg_id])['SecurityGroups'][0]
        ingress_rules_to_revoke = []

        for ip_permission in sg_details['IpPermissions']:
            # Check for overly permissive ingress rules (e.g., 0.0.0.0/0)
            if 'IpRanges' in ip_permission:
                for ip_range in ip_permission['IpRanges']:
                    if ip_range.get('CidrIp') == '0.0.0.0/0':
                        # This is an overly permissive rule
                        ingress_rules_to_revoke.append(ip_permission)
                        logger.warning(f"Identified overly permissive ingress rule in SG {sg_id}: {ip_permission}")

        if ingress_rules_to_revoke:
            logger.info(f"Revoking {len(ingress_rules_to_revoke)} overly permissive ingress rules from SG: {sg_id}")
            ec2_client.revoke_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=ingress_rules_to_revoke
            )
            logger.info(f"Successfully revoked overly permissive ingress rules from SG: {sg_id}")
            return {"status": "success", "message": f"Revoked overly permissive ingress rules from SG {sg_id}."}
        else:
            logger.info(f"No overly permissive ingress rules found for SG: {sg_id}. No action needed.")
            return {"status": "no_action", "message": f"No overly permissive rules found for SG {sg_id}."}

    except ClientError as e:
        logger.error(f"Failed to remediate Security Group {sg_id}: {e}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during SG remediation for {sg_id}: {e}", exc_info=True)
        raise

def lambda_handler(event, context):
    """
    Lambda handler function for Remediation Orchestrator.
    Triggered by AWS Step Functions.
    """
    logger.info(f"Received event from Step Functions: {json.dumps(event)}")

    if not SNS_ANOMALY_TOPIC_ARN:
        logger.error("Missing SNS_ANOMALY_TOPIC_ARN environment variable.")
        return {
            'statusCode': 500,
            'body': json.dumps('Configuration error: Missing SNS_ANOMALY_TOPIC_ARN.')
        }

    action = event.get('action')
    resource_id = event.get('resourceId')
    anomaly_details = event.get('anomalyDetails', {}) # Full anomaly context

    if not action or not resource_id:
        logger.error("Missing 'action' or 'resourceId' in input payload.")
        return {
            'statusCode': 400,
            'body': json.dumps('Bad Request: Missing action or resourceId.')
        }

    remediation_result = {"status": "failed", "message": "Unknown action or unexpected error."}
    try:
        if action == "remediate_s3_public_access":
            remediation_result = remediate_s3_public_access(resource_id)
        elif action == "remediate_security_group":
            remediation_result = remediate_security_group(resource_id)
        # Add more remediation actions here as needed
        else:
            logger.warning(f"Unknown remediation action: {action}. No action taken for {resource_id}.")
            remediation_result = {"status": "skipped", "message": f"Unknown action '{action}'."}

        # Publish remediation status to SNS
        subject = f"Egress Remediation Status: {remediation_result['status'].upper()} for {action} on {resource_id}"
        message = f"Remediation Action: {action}\n" \
                  f"Resource ID: {resource_id}\n" \
                  f"Status: {remediation_result['status']}\n" \
                  f"Message: {remediation_result['message']}\n" \
                  f"Anomaly Details: {json.dumps(anomaly_details, indent=2)}"
        sns_client.publish(TopicArn=SNS_ANOMALY_TOPIC_ARN, Subject=subject, Message=message)

        return {
            'statusCode': 200,
            'body': json.dumps(remediation_result)
        }

    except Exception as e:
        logger.error(f"Error during remediation for action '{action}' on '{resource_id}': {e}", exc_info=True)
        error_message = f"Remediation failed for action '{action}' on '{resource_id}'. Error: {e}"
        remediation_result = {"status": "failed", "message": error_message}
        # Publish failure alert
        sns_client.publish(
            TopicArn=SNS_ANOMALY_TOPIC_ARN,
            Subject=f"CRITICAL: Egress Remediation Failed for {action} on {resource_id}",
            Message=f"{error_message}\nFull event: {json.dumps(event)}"
        )
        return {
            'statusCode': 500,
            'body': json.dumps(remediation_result)
        }