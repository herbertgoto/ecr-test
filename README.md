# Implementing cost, vulnerability, and usage reporting for Amazon ECR

AWS users have been adopting Amazon Elastic Container Registry (ECR) as their container image repository due to its ease of use and seamless integration with AWS container services. With the increasing adoption of ECR, there is a growing demand for centralized cost, usage and security reports. This code sample introduces a comprehensive solution that provides valuable insights into repository usage metrics and costs. By running this code sample, you can gain a deeper understanding of resource consumption and optimize costs effectively.

## Before you start

1. [Docker](https://docs.docker.com/get-docker/) (or any other container build tool) installed in your environment
2. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed in your environment
3. An IAM principal (user or role) with [this policy]
4. Git

## Project Structure
```
├── src/
│   ├── app.py
│   └── requirements.txt
└── Dockerfile
```

## Getting Started

Follow these steps to run the project:

1. **Clone the project**
   ```bash
   git clone https://github.com/aws-samples/amazon-ecr-cost-vulnerability-and-usage-reporting.git
   ```

2. **Build the Docker image**
   ```bash
   cd amazon-ecr-cost-vulnerability-and-usage-reporting
   docker build -t ecr-reporter:v0.1.0 .
   ```
   
   This command builds a Docker image with the following parameters:
   - `-t ecr-reporter:v0.1.0`: Tags the image with the name "ecr-reporter" and the tag "v0.1.0". You can replace the name and tag with any values you want. 
   - `.`: Uses the Dockerfile in the current directory as the build context

3. **Set IAM credentials in your environment**

   There are many ways to configure IAM credentials for your environment. For this walkthrough, we use:

   ```bash
   aws configure --profile <your-profile-name>
   ```

   This command will request you for: AWS Access Key ID, AWS Secret Access Key, AWS Session Token, Default region name, and Default output format.   

4. **Generate the summary report**

   Use the following command to generate the repositories summary report:

   ```bash
   docker run \
      -e AWS_ACCESS_KEY_ID=$(aws --profile <your profile name> configure get aws_access_key_id) \
      -e AWS_SECRET_ACCESS_KEY=$(aws --profile <your profile name> configure get aws_secret_access_key) \
      -e AWS_DEFAULT_REGION=<aws region code> \
      -e AWS_SESSION_TOKEN=$(aws --profile <your profile name> configure get aws_session_token)] \
      -v <path to the directory where the report will be saved>:/data \
      ecr-reporter:v0.1.0
   ```

   Replace the following placeholders:
   - `<path to the directory where the report will be saved>`: Local directory path where the CSV reports will be saved
   - `<your profile name>`: The name of the AWS CLI profile you used when configured your IAM credentials in step 3
   - `<aws region code>`: Code of the AWS region you are using. i.e us-east-1

   Optional parameters:
   - `LOG_VERBOSITY`: Set to `DEBUG`, `INFO`, `WARNING`, or `ERROR` (default: `INFO`)
   - `DECIMAL_SEPARATOR`: Set to `.` or `,` for CSV number formatting (default: `.`)

   ### Understanding the reports

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

5. **Generate the image-level report**

   Use the following command to generate the image-level report for image `foobar`:

   ```bash
   docker run \
      -e AWS_ACCESS_KEY_ID=$(aws --profile <your profile name> configure get aws_access_key_id) \
      -e AWS_SECRET_ACCESS_KEY=$(aws --profile <your profile name> configure get aws_secret_access_key) \
      -e AWS_DEFAULT_REGION=<aws region code> \
      -e AWS_SESSION_TOKEN=$(aws --profile <your profile name> configure get aws_session_token)] \
      -e REPORT=foobar
      -v <path to the directory where the report will be saved>:/data \
      ecr-reporter:v0.1.0
   ```
   To generate an image-level report, we set the environment variable `REPORT` to the name of the repository.

   Please remember to replace the placeholders with your own values as you did in step 3.
  
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