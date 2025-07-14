# AWS Egress Cost Optimizer: AI-Powered Data Transfer Anomaly Detection & Remediation

## Overview

In the dynamic world of cloud computing, managing and optimizing data transfer costs, especially egress (data leaving AWS), is a persistent challenge. These costs can be hazy, unpredictable, and often a significant portion of the AWS bill.

This sample solution provides an advanced, AI/ML-driven framework to proactively identify, analyze, and even remediate unexpected spikes in AWS data egress. By leveraging a suite of AWS services, including Amazon Bedrock and SageMaker, I have transformed reactive cost management into a proactive, intelligent, and continuously optimizing FinOps practice.

## Detailed Documentation

For a comprehensive understanding of this solution, including the problem it solves, its architecture, implementation details, and operational guidance, please refer to the detailed documentation pages:

1. [Problem & Solution Overview](./docs/01_problem_and_solution.MD)

    - A deep dive into the challenges of egress cost management and the high-level solution we propose.

2. [Architecture Deep Dive](./docs/02_architecture.MD)

    - Visual representation using C4 Model diagrams and a detailed AWS Infrastructure Architecture diagram with component explanations.

3. [Infrastructure (Terraform)](./docs/03_terraform.MD)

    - Detailed breakdown of the AWS resources provisioned by Terraform, organized by modules.

4. [Sentinel Policies](./docs/04_sentinel_policies.MD)

    - Explanation of the pre-deployment governance policies that ensure infrastructure compliance.

5. [Application Logic (Lambda & Bedrock)](./docs/05_application_logic.MD)

    - Details on the serverless functions that drive anomaly detection, AI analysis, and orchestration.

6. [Data Processing Scripts (Glue & SageMaker)](./docs/06_data_processing_scripts.MD)

    - Information on the ETL and feature engineering scripts that transform raw logs into actionable data.

7. [ML Models (SageMaker)](./docs/07_ml_models.MD)

    - Comprehensive overview of the machine learning models, training, inference, and development notebooks.

8. [Utility Scripts](./docs/08_utility_scripts.MD)

    - Helper scripts for prerequisites setup and data simulation.

9. [CI/CD Pipeline (GitHub Actions)](./docs/09_cicd_pipeline.MD)

    - Detailed explanation of the automated deployment pipeline.

10. [Implementation Guide](./docs/10_implementation_guide.MD)

    - A step-by-step guide to deploy and configure the solution in your AWS account.

## Repository Structure

```text
aws-egress-cost-optimizer/
├── cicd/                     # GitHub Actions CI/CD workflows
├── docs/                     # Detailed documentation pages
│   ├── 01_problem_and_solution.md
│   ├── 02_architecture.md
│   ├── ... (and more)
│   └── diagrams/             # Diagrams and images for documentation
├── infrastructure/           # All Terraform configurations
│   ├── modules/
│   └── ...
├── data_processing_scripts/  # Python/Spark scripts for Glue and SageMaker Processing
├── ml_models/                # ML model training/inference scripts, notebooks, artifacts
├── application_logic/        # Lambda function code, Bedrock prompts
├── scripts/                  # Auxiliary shell/python scripts
├── sentinel/                 # HashiCorp Sentinel policies for IaC validation
├── .gitignore
├── README.md
└── LICENSE
```

## Getting Started

To begin exploring or deploying this solution, start by reviewing the [Implementation Guide](./docs/10_implementation_guide.MD).

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.