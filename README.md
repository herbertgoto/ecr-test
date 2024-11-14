# Implementing cost, vulnerability, and usage reporting for Amazon ECR

AWS users have been adopting Amazon Elastic Container Registry (ECR) as their container image repository due to its ease of use and seamless integration with AWS container services. With the increasing adoption of ECR, there is a growing demand for centralized cost, usage and security reports. This blog post introduces a comprehensive solution that provides valuable insights into repository usage metrics and costs through Athena queries. By leveraging the power of ECR and Athena, you can gain a deeper understanding of resource consumption and optimize costs effectively. Additionally, the solution offers the ability to set up notifications when a repository's storage exceeds a predefined threshold, enabling proactive monitoring and cost control.

## Before you start

1. [Docker](https://docs.docker.com/get-docker/) installed on your machine
2. Git (optional, for cloning the repository)
3. Make sure your IAM principal has the necessary permissions to run the commands (you find those permissions in /assets/iam_policy.json)

## Project Structure
```
├── src/
│   ├── app.py
│   └── requirements.txt
└── Dockerfile
```

## Getting Started

Follow these steps to run the project:

1. **Clone or create the project**
   ```bash
   git clone <repository-url>
   # or create the directories manually
   ```

2. **Build the Docker image**
   ```bash
   docker build -t my-app .
   ```
   
   This command builds a Docker image with the following parameters:
   - `-t my-app`: Tags the image with the name "my-python-app"
   - `.`: Uses the Dockerfile in the current directory as the build context

   Make sure you're in the root directory of the project when running this command.

3. **Run the container**

   Use the following command to run the container, replacing the placeholders with your specific values:

   ```bash
   docker run \
     -e AWS_ACCESS_KEY_ID=$(aws --profile <aws profile name> configure get aws_access_key_id) \
     -e AWS_SECRET_ACCESS_KEY=$(aws --profile <aws profile name> configure get aws_secret_access_key) \
     -e AWS_DEFAULT_REGION=<aws region code> \
     [-e AWS_SESSION_TOKEN=$(aws --profile <aws profile name> configure get aws_session_token)] \
     [-e LOG_VERBOSITY=<log verbosity>] \
     [-e DECIMAL_SEPARATOR=<decimal separator>] \
     -v <path to the directory where the report will be saved>:/data \
     <container-name>:<tag>
   ```

   Replace the following placeholders:
   - `<aws profile name>`: Your AWS CLI profile name (e.g., `default`)
   - `<aws region code>`: Your AWS region (e.g., `us-east-1`)
   - `<path to the directory where the report will be saved>`: Local directory path where the CSV reports will be saved
   - `<container-name>`: Name of the container image you built (e.g., `my-python-app`)
   - `<tag>`: Tag of the container image (e.g., `latest`)

   Optional parameters:
   - `AWS_SESSION_TOKEN`: Required only if you're using temporary credentials
   - `LOG_VERBOSITY`: Set to `DEBUG`, `INFO`, `WARNING`, or `ERROR` (default: `INFO`)
   - `DECIMAL_SEPARATOR`: Set to `.` or `,` for CSV number formatting (default: `.`)

   Example command:
   ```bash
   docker run \
     -e AWS_ACCESS_KEY_ID=$(aws --profile default configure get aws_access_key_id) \
     -e AWS_SECRET_ACCESS_KEY=$(aws --profile default configure get aws_secret_access_key) \
     -e AWS_DEFAULT_REGION=us-east-1 \
     -v ~/ecr-reports:/data \
     my-python-app:latest
   ```

## Understanding the reports

After you run the container, you will find two CSV files in the directory you specified:

- `repositories_summary.csv`: contains a summary of the repositories and their storage utilization. This report contains the following attributes:

| Field | Description |
|-------|-------------|
| `repositoryName` | The name of the repository |
| `createdAt` | The date when the repository was created |
| `scanOnPush` | Whether the repository has image scanning enabled |
| `totalImages` | The total number of images in the repository |
| `totalSize(MB)` | The total size of the images in the repository in MB |
| `monthlyStorageCost(USD)` | The monthly storage cost in USD |
| `hasBeenPulled` | Whether the repository has been pulled at least once |
| `lastRecordedPullTime` | The date when the repository was last pulled |
| `daysSinceLastPull` | The number of days since the repository was last pulled |
| `lifecyclePolicyText` | The lifecycle policy text of the repository |

The contents of this report facilitate to identify the repositories that are not being used and can be deleted to reduce costs. It also allows to identify which repositories have the most images, the most heaviest images ones, and the ones without lifecycle policies; which influences the cost of the repository.

- `images_summary.csv`: contains a summary of the images and their storage utilization. This report contains the following attributes:

| Field | Description |
|-------|-------------|
| `repositoryName` | The name of the repository |
| `imageTags` | The tags of the image |
| `imagePushedAt` | The date when the image was pushed |
| `imageSize(MB)` | The size of the image in MB |
| `imageScanStatus` | The scan status of the image |
| `imageScanCompletedAt` | The date when the image was last scanned |
| `findingSeverityCounts` | The severity counts of the findings in the image |
| `lastRecordedPullTime` | The date when the image was last pulled |
| `daysSinceLastPull` | The number of days since the image was last pulled |

The contents of this report allows to do a deep dive into the images and their storage utilization, which facilitates to identify the images that are not being used and can be deleted to reduce costs. It can also provide more insights to implement more adequate lifecycle policies. Finally, it also facilitates to identify which images have the most findings, which facilitates to identify the images that are most affected by vulnerabilities and can be prioritized for remediation.

## Security Notes

- The application runs as a non-root user inside the container for enhanced security
- Python bytecode generation is disabled
- Unbuffered output is enabled for better logging in containerized environments

## Troubleshooting

- If you encounter permission issues, ensure your `src/` directory and files have appropriate permissions
- For Docker build issues, verify that your Docker daemon is running
- Check that all required files are in the correct locations as per the project structure

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.