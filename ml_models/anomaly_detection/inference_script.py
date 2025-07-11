# Inference script for AWS SageMaker endpoint using Isolation Forest for anomaly detection

import os
import json
import logging
import pandas as pd
import joblib # For loading scikit-learn models
import numpy as np # For numerical operations
import io # For handling CSV input

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# The directory where the model artifacts are stored within the inference container
MODEL_PATH = '/opt/ml/model'

def model_fn(model_dir):
    """
    Deserializes and loads the trained model from the model_dir.
    This function is called once when the endpoint container starts up.
    """
    try:
        model = joblib.load(os.path.join(model_dir, 'model.joblib'))
        logger.info("Model loaded successfully.")
        return model
    except Exception as e:
        logger.error(f"Error loading model from {model_dir}: {e}")
        raise

def input_fn(request_body, request_content_type):
    """
    Deserializes the input data from the request body into a Pandas DataFrame.
    This function is called for each inference request.
    It should handle the content types your endpoint will receive (e.g., application/json, text/csv).
    """
    if request_content_type == 'application/json':
        data = json.loads(request_body)
        # Assuming input data is a list of dictionaries, where each dict is a data point
        # Example: [{"daily_egress_cost_usd": 100, "daily_egress_usage_amount": 100000, ...}]
        df = pd.DataFrame(data)
        logger.info(f"JSON input parsed. DataFrame shape: {df.shape}")
        return df
    elif request_content_type == 'text/csv':
        # Assuming CSV input with headers, or without if you handle columns explicitly
        df = pd.read_csv(io.StringIO(request_body))
        logger.info(f"CSV input parsed. DataFrame shape: {df.shape}")
        return df
    else:
        raise ValueError(f"Unsupported content type: {request_content_type}. "
                         "This endpoint supports 'application/json' and 'text/csv'.")

def predict_fn(input_data, model):
    """
    Performs predictions using the loaded model.
    This function is called after input_fn.
    The Isolation Forest model's `predict` method returns -1 for outliers and 1 for inliers.
    """
    logger.info(f"Received input data for prediction. Shape: {input_data.shape}")
    # Ensure input data has the same numerical features as used during training
    # Select only numerical columns for prediction, matching the training script's feature selection.
    features_for_prediction = input_data.select_dtypes(include=np.number)
    if features_for_prediction.empty:
        raise ValueError("No numerical features found in input data for prediction. Check input schema.")

    predictions = model.predict(features_for_prediction)

    # Convert Isolation Forest output (-1 for outlier, 1 for inlier) to a more intuitive format (1 for anomaly, 0 for normal).
    is_anomaly = (predictions == -1).astype(int)
    logger.info(f"Predictions generated. Anomalies detected: {np.sum(is_anomaly)}")

    # Return a DataFrame or Series that includes original data and anomaly score
    # This allows the calling Lambda to get context.
    input_data['is_anomaly'] = is_anomaly
    input_data['anomaly_score'] = model.decision_function(features_for_prediction) # Lower score means more anomalous

    return input_data # Return the DataFrame with added prediction columns

def output_fn(prediction_output, accept_content_type):
    """
    Serializes the prediction result to the desired content type.
    This function is called after predict_fn.
    """
    if accept_content_type == 'application/json':
        # Convert the DataFrame output to JSON
        return prediction_output.to_json(orient='records'), accept_content_type
    elif accept_content_type == 'text/csv':
        # Convert the DataFrame output to CSV
        return prediction_output.to_csv(index=False), accept_content_type
    else:
        raise ValueError(f"Unsupported accept type: {accept_content_type}. "
                         "This endpoint supports 'application/json' and 'text/csv'.")