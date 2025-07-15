# 7. ML Models (SageMaker)

This section provides a comprehensive overview of the machine learning components, focusing on the anomaly detection model, its training, and deployment using Amazon SageMaker.

## 7.1. Overview

The core of the AI/ML capability lies in detecting anomalous patterns in egress costs. We utilize an unsupervised anomaly detection approach, as anomalies are rare and often don't have predefined labels.

- **Model Type:** Isolation Forest (from scikit-learn).
- **Purpose:** To learn the "normal" patterns of data egress from historical data and identify new data points that deviate significantly from these patterns.
- **Output:** For each data point, the model predicts whether it's an inlier (normal) or an outlier (anomaly) and provides an anomaly score.

## 7.2. Model Training (`ml_models/anomaly_detection/training_script.py`)

This Python script is executed by an Amazon SageMaker Training Job to train the Isolation Forest model.

- **Input Data:** The script expects processed and feature-engineered data (e.g., `processed_features.parquet`) from the S3 Processed Data Bucket, typically provided via SageMaker's `SM_CHANNEL_TRAIN` environment variable.
- **Hyperparameters:** Configurable parameters for the Isolation Forest model:

    - `n_estimators`: The number of base estimators (trees) in the ensemble.
    - `contamination`: The expected proportion of outliers in the data set. This parameter is used to define the threshold for anomaly detection.
    - `random_state`: For reproducibility of results.

- **Training Process:**

    - Loads the input data into a Pandas DataFrame.
    - Selects only numerical features for the Isolation Forest model.
    - Initializes and fits the IsolationForest model to the training data.

- **Model Artifact Output:** Saves the trained scikit-learn model as model.joblib to the `SM_MODEL_DIR` directory. SageMaker then compresses the contents of this directory into a `model.tar.gz` file and uploads it to the S3 Model Artifacts Bucket.

## 7.3. Model Inference (`ml_models/anomaly_detection/inference_script.py`)

This Python script defines the functions necessary for a SageMaker Endpoint to serve real-time predictions.

- `model_fn(model_dir)`:

    - Called once when the SageMaker endpoint container starts.
    - Loads the trained `model.joblib` file from the `model_dir` (which contains the extracted `model.tar.gz` content).

- `input_fn(request_body, request_content_type)`:

    - Called for each inference request.
    - Deserializes the incoming request body (e.g., JSON or CSV) into a Pandas DataFrame.
    - <code style="color : green">**Note:** The input data should contain the same features (and in the same format) as the data used for training after feature engineering.</code>

- `predict_fn(input_data, model)`:

    - Called after `input_fn`.
    - Performs predictions using the loaded `model` on the `input_data`.
    - The `model.predict()` method returns 1 for inliers (normal) and -1 for outliers (anomalies). This is converted to `0` for normal and `1` for anomaly for clarity.
    - Also calculates and includes the `anomaly_score` (decision function output), where lower scores indicate a higher likelihood of being an anomaly.
    - Returns the input data augmented with `is_anomaly` and `anomaly_score` columns.

- `output_fn(prediction_output, accept_content_type)`:

    - Serializes the prediction results (the augmented DataFrame) back into the desired format (e.g., JSON or CSV) for the calling service (e.g., AWS Lambda).

## 7.4. Model Development & Experimentation (`ml_models/anomaly_detection/notebooks/`)

The notebooks/ directory contains conceptual Jupyter notebooks designed for use with a SageMaker Notebook Instance.

### 7.4.1. `anomaly_detection_eda.ipynb` (Conceptual)

- **Purpose:** Exploratory Data Analysis (EDA) of the raw and processed egress cost data.
- **Key Activities:**

    - Loading data from the S3 Processed Data Bucket.
    - Visualizing egress cost trends over time (daily, hourly).
    - Analyzing cost distribution by service, region, and usage type.
    - Identifying initial patterns, seasonality, and potential outliers.
    - Understanding the characteristics of VPC Flow Log data (source/destination IPs, ports, bytes).
    - Helps in understanding the data before building the model.

### 7.4.2. `model_training.ipynb` (Conceptual)

- **Purpose:** Orchestrating SageMaker Training Jobs and deploying test endpoints for the anomaly detection model.
- **Key Activities:**

    - Setting up SageMaker session and roles.
    - Preparing training data inputs (pointing to S3 paths of processed features).
    - Configuring and launching a SageMaker `SKLearn Estimator` to run the `training_script.py`.
    - Monitoring training job progress.
    - Optionally, deploying a temporary SageMaker Endpoint for quick testing of the `inference_script.py` with sample data.
    - <code style="color : red">**Important:** This notebook is for interactive development and testing. Production model deployments are handled by Terraform.</code>

These ML components form the intelligence layer of the solution, enabling automated identification of anomalous egress patterns that warrant further investigation and potential remediation.

