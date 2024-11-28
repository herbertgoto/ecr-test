# Implementing cost, vulnerability, and usage reporting for Amazon ECR

AWS users have been adopting Amazon Elastic Container Registry (ECR) as their container image repository due to its ease of use and seamless integration with AWS container services. With the increasing adoption of ECR, there is a growing demand for centralized cost, usage, and security reports. This code sample provides valuable insights into repository usage metrics and costs. By running this code sample, you can gain a deeper understanding of resource consumption, security posture, and costs optimization opportunities.

## Solution Overview

The sample code generates two reports:

   - A summary for the repositories in a registry that contains the following key attributes:

   | Field | Description |
   |-------|-------------|
   | `repositoryName` | The name of the repository |
   | `createdAt` | The date when the repository was created |
   | `scanOnPush` | Whether images are scanned after being pushed to a repository |
   | `totalImages` | The total number of images in the repository |
   | `totalSize(MB)` | The combined size of the images in the repository in MB |
   | `hasBeenPulled` | Whether the repository has been pulled at least once |
   | `lastRecordedPullTime` | The date when the repository was last pulled |
   | `daysSinceLastPull` | The number of days since the repository was last pulled |
   | `lifecyclePolicyText` | The lifecycle policy text of the repository |

   The contents of this report help to identify the repositories that are not being used and can be deleted to reduce costs. The contents also allows to identify which repositories have the most images, the most heaviest ones, and the ones without lifecycle policies; which impacts the cost of the repository. Last but not least, this report allows to see which repositories have security scan enabled in a consolidated way.

   > [!CAUTION]
   > The totalSize(MB) field sums the size of the images in the repository which may provide you with insights about repositories that are consuming more storage and therefore may be candidates for optimization. However, this field cannot be used to determine the storage cost for each repository. Amazon ECR does not apply duplicate charges for container layers, which means that if you have several images with the same layer, it will only be counted once for pricing purposes. To obtain the exact storage cost for each repository, you would need to identify the different layers within all images of the repository and calculate the cost based on the size of the unique layers combined.

   - An image-level report that contains key attributes of all images/artifacts within a repository. This report contains the following attributes:

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

   The contents of this report allows to dive deep into the images and their storage utilization, which helps to identify which ones are not being used and can be deleted to reduce costs. The contents can also provide insights to implement more adequate lifecycle policies. Finally, this report also facilitates to track images that have the most and more critical security findings, which helps to prioritize them for remediation.

## Before you start

1. [Docker](https://docs.docker.com/get-docker/) (or any other container build tool) installed in your environment
2. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed in your environment
3. An IAM principal (user or role) with [this policy](assets/ecr_permissions.json)
4. Git

## Project Structure
```
├── assets/
│   ├── ecr_permissions.json
│   ├── s3_permissions.json
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

   There are many ways to configure IAM credentials for your environment. One way to do it is by using the AWS CLI:

   ```bash
   aws configure --profile <your-profile-name>
   ```

   This command will request you for: AWS Access Key ID, AWS Secret Access Key, AWS Session Token, Default region name, and Default output format.  


> [!CAUTION]
> We do not recommend using long-term credentials for this solution. Instead, we recommend using temporary credentials. We also recommend using a principal with the least privileges needed to run the solution. The specific permissions required can be found [here](assets/ecr_permissions.json). Security best practices in AWS IAM can be found [here](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html).

4. **Generate the summary report**

   Use the following command to generate the repositories summary report:

   ```bash
   docker run \
      -e AWS_ACCESS_KEY_ID=$(aws --profile <your profile name> configure get aws_access_key_id) \
      -e AWS_SECRET_ACCESS_KEY=$(aws --profile <your profile name> configure get aws_secret_access_key) \
      -e AWS_DEFAULT_REGION=<aws region code> \
      [-e AWS_SESSION_TOKEN=$(aws --profile <your profile name> configure get aws_session_token)] \
      [-e LOG_VERBOSITY=<log verbosity level>] \
      [-e AWS_S3_BUCKET=<s3 bucket name>] \
      [-e DECIMAL_SEPARATOR=<decimal separator>] \
      [-v <path to the directory where the report will be saved>:/data] \
      <image name>:<image tag>
   ```

   Replace the following placeholders:
   - `<path to the directory where the report will be saved>`: Local directory path where the CSV reports will be saved
   - `<your profile name>`: The name of the AWS CLI profile you used when configured your IAM credentials in step 3
   - `<aws region code>`: Code of the AWS region you are using. i.e us-east-1
   - `<image name>`: The name of the image to be used. i.e ecr-reporter
   - `<image tag>`: The tag of the image to be used. i.e v0.1.0

   Optional parameters:
   - `AWS_SESSION_TOKEN`: Set to the session token if you are using temporary credentials.
   - `LOG_VERBOSITY`: Set to `DEBUG`, `INFO`, `WARNING`, or `ERROR` (default: `INFO`).
   - `DECIMAL_SEPARATOR`: Set to `.` or `,` for CSV number formatting (default: `.`).
   - `AWS_S3_BUCKET`: Set to the name of the S3 bucket where the report will be saved. If not set, the report will be saved locally to the container.
   - `<path to the directory where the report will be saved>`: Set to the path to the directory where the report will be saved. If not set, the report will be saved locally to the container.
   ### Understanding the reports

5. **Generate the image-level report**

   Use the following command to generate the image-level report:

   ```bash
   docker run \
      -e AWS_ACCESS_KEY_ID=$(aws --profile <your profile name> configure get aws_access_key_id) \
      -e AWS_SECRET_ACCESS_KEY=$(aws --profile <your profile name> configure get aws_secret_access_key) \
      -e AWS_DEFAULT_REGION=<aws region code> \
      -e REPORT=<repository name> \
      [-e AWS_SESSION_TOKEN=$(aws --profile <your profile name> configure get aws_session_token)] \
      [-e LOG_VERBOSITY=<log verbosity level>] \
      [-e AWS_S3_BUCKET=<s3 bucket name>] \
      [-e DECIMAL_SEPARATOR=<decimal separator>] \
      [-v <path to the directory where the report will be saved>:/data] \
      <image name>:<image tag>
   ```

   To generate an image-level report, we set the environment variable `REPORT` to the name of the repository.

   Please remember to replace the placeholders with your own values as you did in step 4.
  
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