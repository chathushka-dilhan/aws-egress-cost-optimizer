# This script is designed to run as a SageMaker training job for anomaly detection using the Isolation Forest algorithm.

import argparse
import os
import logging
import pandas as pd
from sklearn.ensemble import IsolationForest
import joblib # For saving/loading scikit-learn models
import json
import numpy as np

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()

    # SageMaker specific arguments. These are passed as environment variables by SageMaker.
    # SM_OUTPUT_DATA_DIR: Directory where any output data (e.g., evaluation metrics) should be saved.
    # SM_MODEL_DIR: Directory where the trained model artifact should be saved.
    # SM_CHANNEL_TRAIN: Path to the training data.
    parser.add_argument('--output-data-dir', type=str, default=os.environ.get('SM_OUTPUT_DATA_DIR'))
    parser.add_argument('--model-dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAIN'))

    # Model hyperparameters. These can be tuned via SageMaker Hyperparameter Tuning.
    parser.add_argument('--n_estimators', type=int, default=100, help='Number of base estimators in the ensemble.')
    parser.add_argument('--contamination', type=float, default=0.01,
                        help='The proportion of outliers in the data set. Used to define the threshold.')
    parser.add_argument('--random_state', type=int, default=42, help='Random state for reproducibility.')

    args = parser.parse_args()

    logger.info(f"Training data path: {args.train}")
    logger.info(f"Model output path: {args.model_dir}")

    # Load training data from the SageMaker training channel.
    # This data is expected to be the processed features from the SageMaker Processing job.
    input_files = [os.path.join(args.train, file) for file in os.listdir(args.train)]
    if not input_files:
        raise ValueError('No input files found in the training channel. Ensure data is correctly passed.')

    # Concatenate all Parquet files in the input directory.
    # Assuming the processed features are in Parquet format.
    try:
        df = pd.concat([pd.read_parquet(file) for file in input_files])
        logger.info(f"Loaded {len(df)} rows for training from {len(input_files)} files.")
    except Exception as e:
        logger.error(f"Error loading training data: {e}")
        raise

    # --- Prepare features for the model ---
    # The Isolation Forest model expects numerical features.
    # The 'feature_engineering.py' script should have already transformed categorical features
    # and scaled numerical ones.
    # We assume all columns in the input DataFrame are features for the model.
    features = df.select_dtypes(include=np.number) # Select only numerical columns for Isolation Forest
    if features.empty:
        raise ValueError("No numerical features found in the training data. Check feature engineering output.")

    # Initialize and train the Isolation Forest model
    logger.info(f"Training Isolation Forest model with hyperparameters: "
                f"n_estimators={args.n_estimators}, contamination={args.contamination}, random_state={args.random_state}")
    model = IsolationForest(
        n_estimators=args.n_estimators,
        contamination=args.contamination,
        random_state=args.random_state
    )
    model.fit(features)
    logger.info("Model training complete.")

    # Save the trained model artifact.
    # SageMaker expects the model to be saved in the `SM_MODEL_DIR` directory.
    # The entire content of this directory will be compressed into `model.tar.gz`.
    model_path = os.path.join(args.model_dir, 'model.joblib')
    joblib.dump(model, model_path)
    logger.info(f"Model saved to {model_path}")

    # Optional: Save a small evaluation report or metadata if needed
    # For example, save the number of features used, training duration, etc.
    metrics_path = os.path.join(args.output_data_dir, 'metrics.json')
    with open(metrics_path, 'w') as f:
        json.dump({"training_status": "success", "num_features": features.shape[1]}, f)
    logger.info(f"Metrics saved to {metrics_path}")

