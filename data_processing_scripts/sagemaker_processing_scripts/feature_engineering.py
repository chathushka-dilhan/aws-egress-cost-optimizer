# This script is designed to run as a SageMaker Processing job for feature engineering.
# It processes data from AWS Cost and Usage Reports (CUR) and VPC Flow Logs
# to create features suitable for anomaly detection in egress costs.

import argparse
import os
import logging
import pandas as pd
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
import numpy as np
import scipy.sparse
import joblib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()

    # SageMaker Processing job arguments
    parser.add_argument('--input-data-dir', type=str, default=os.environ.get('SM_INPUT_DATA_DIR'))
    parser.add_argument('--output-data-dir', type=str, default=os.environ.get('SM_OUTPUT_DATA_DIR'))

    args = parser.parse_args()

    input_files = [os.path.join(args.input_data_dir, file) for file in os.listdir(args.input_data_dir)]
    if not input_files:
        raise ValueError('No input files found for processing.')

    # Assuming input data is Parquet from Glue jobs (CUR and Flow Logs)
    # This script would typically combine and join data from different sources
    # For simplicity, we'll assume a single input for now, but in reality,
    # you'd have multiple input channels for different data sources.
    df = pd.concat([pd.read_parquet(file) for file in input_files])
    logger.info(f"Loaded {len(df)} rows for feature engineering.")

    # --- Feature Engineering Steps ---

    # 1. Time-based features (from 'usage_date' or 'flow_date')
    df['date'] = pd.to_datetime(df['usage_date']) # Assuming 'usage_date' from CUR
    df['day_of_week'] = df['date'].dt.dayofweek # Monday=0, Sunday=6
    df['day_of_month'] = df['date'].dt.day
    df['month'] = df['date'].dt.month
    df['week_of_year'] = df['date'].dt.isocalendar().week.astype(int)
    df['is_weekend'] = df['day_of_week'].isin([5, 6]).astype(int)

    # 2. Lag features (e.g., egress from previous day/week)
    # This requires sorting and grouping, which can be complex for a generic script.
    # For a real implementation, ensure data is sorted and grouped correctly before applying lags.
    # Example (conceptual, requires proper grouping and sorting):
    # df['egress_bytes_lag_1d'] = df.groupby(['service_code', 'region'])['daily_egress_usage_amount'].shift(1)
    # df['egress_bytes_rolling_7d_avg'] = df.groupby(['service_code', 'region'])['daily_egress_usage_amount'].rolling(window=7).mean().reset_index(level=[0,1], drop=True)

    # 3. Ratio features (e.g., egress_bytes / total_bytes_in_region)
    # Requires total bytes, which might come from another data source or aggregation.

    # 4. Categorical features encoding (e.g., 'service_code', 'region', 'usage_type')
    categorical_features = ['service_code', 'region', 'usage_type', 'day_of_week', 'month']
    numerical_features = ['daily_egress_cost_usd', 'daily_egress_usage_amount'] # Features for anomaly detection

    # Create a preprocessor pipeline for numerical and categorical features
    preprocessor = ColumnTransformer(
        transformers=[
            ('num', StandardScaler(), numerical_features),
            ('cat', OneHotEncoder(handle_unknown='ignore'), categorical_features)
        ])

    logger.info("Fitting preprocessor and transforming data...")
    # Fit and transform the data
    transformed_data = preprocessor.fit_transform(df)

    # Ensure transformed_data is a dense NumPy array before creating DataFrame
    # ColumnTransformer can return a sparse matrix if OneHotEncoder is used and sparse_output=True (default in newer versions)
    # or if any transformer returns sparse output.
    if scipy.sparse.issparse(transformed_data):
        transformed_data = transformed_data.toarray()
    # If it's already a numpy array, no conversion is needed.

    # Get feature names after one-hot encoding
    # Ensure preprocessor.named_transformers_['cat'] is an OneHotEncoder before calling get_feature_names_out
    ohe_feature_names = preprocessor.named_transformers_['cat'].get_feature_names_out(categorical_features)
    all_feature_names = numerical_features + list(ohe_feature_names)

    # Convert transformed data back to DataFrame
    df_transformed = pd.DataFrame(transformed_data, columns=all_feature_names)
    logger.info(f"Transformed data shape: {df_transformed.shape}")
    logger.info(df_transformed.head())

    # --- Save Processed Features ---
    # Save the processed features to the output directory, which SageMaker will upload to S3.
    output_path = os.path.join(args.output_data_dir, 'processed_features.parquet')
    df_transformed.to_parquet(output_path, index=False)
    logger.info(f"Processed features saved to {output_path}")

    # Optional: Save the preprocessor object if it needs to be reused for inference
    joblib.dump(preprocessor, os.path.join(args.output_data_dir, 'preprocessor.joblib'))