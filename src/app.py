#!/bin/env python

"""
ECR Cost and Security Report Tool

This script generates reports on Amazon Elastic Container Registry (ECR) repositories and images.
It can create a summary report for all repositories in a registry or a detailed report for images in a specific repository.

Usage:
    Set the REPORT environment variable to 'registry' for a full registry report (this is the default option),
    or to a specific repository name for a detailed image report of that repository.

Environment Variables:
    REPORT: 'registry' or a repository name (default: 'registry')
    LOG_VERBOSITY: Logging level (default: 'INFO') It can be DEBUG, INFO, WARNING, ERROR, or CRITICAL.

Dependencies:
    - boto3
    - pytz
    - python-json-logger
"""

import os
import csv
import logging
import json
from datetime import datetime
from pythonjsonlogger import jsonlogger
import boto3
import pytz

# Set env to scan a registry or a repository. Provide the name of the repository as env (e.g. REPORT=nginx).
report = os.environ.get('REPORT', 'registry')
log_service_name = os.environ.get('LOG_SERVICE_NAME', 'ECRTool')
log_verbosity = os.environ.get('LOG_VERBOSITY', 'INFO')
decimal_separator = os.environ.get('DECIMAL_SEPARATOR', '.')

# Logging setup
logger = logging.getLogger(log_service_name)
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(fmt="%(asctime)s %(levelname)s %(name)s %(message)s")
logHandler.setFormatter(formatter)
logger.addHandler(logHandler)
logger.setLevel(log_verbosity)

#Boto3 authentication
#session = boto3.Session(e.g. profile_name='my_profile') This if for local tests of python code.
client_ecr = boto3.client('ecr')
sts_client = boto3.client('sts')

# Constants
REPO_REPORT_FILE = 'repositories_summary.csv'
IMAGE_REPORT_FILE = 'images_summary.csv'
MAX_RESULTS = 1000

def get_ecr_repo_cost_report() -> None:
    """
    Creates a report with attributes associated with the costs of an ECR registry.

    This function queries all repositories in the ECR registry, gathers relevant information,
    and writes a summary to a CSV file.

    Raises:
        boto3.exceptions.Boto3Error: If there's an error interacting with AWS services.
        csv.Error: If there's an error writing to the CSV file.
    """
    # Define the columns for the CSV report
    REPO_REPORT_COLUMNS = [
        "repositoryName","createdAt","scanOnPush","totalImages","totalSize(MB)","monthlyStorageCost(USD)",
        "hasBeenPulled","lastRecordedPullTime","daysSinceLastPull","lifecyclePolicyText"
    ]

    try:
        # Query ECR for repository details
        response = client_ecr.describe_repositories(maxResults=MAX_RESULTS)
        repos = []

        while True:
            # Process each repository
            for i in response['repositories']:
                # Compile repository data
                repo = {
                    'repositoryName': i['repositoryName'],
                    'createdAt': i['createdAt'].strftime("%m/%d/%Y %H:%M"),
                    'scanOnPush': i['imageScanningConfiguration']['scanOnPush'],
                }
                repo.update(get_image_summary(i['repositoryName']))
                repo.update(get_lifecycle_policy(i['repositoryName']))
                repos.append(repo)

            # Check for more pages of results
            if 'nextToken' not in response:
                break
            response = client_ecr.describe_repositories(nextToken=response['nextToken'], maxResults=MAX_RESULTS)
            continue

        # Write repository data to CSV file
        with open('/data/'+REPO_REPORT_FILE, mode='a', newline='', encoding='utf-8') as file:
        #with open(REPO_REPORT_FILE, mode='a', newline='') as file:            # This if for local tests of python code.
            writer = csv.DictWriter(file, fieldnames=REPO_REPORT_COLUMNS, delimiter='|')
            writer.writeheader()
            for data in repos:
                data['totalSize(MB)'] = str(data['totalSize(MB)']).replace('.', decimal_separator)
                data['monthlyStorageCost(USD)'] = str(data['monthlyStorageCost(USD)']).replace('.', decimal_separator)
                writer.writerow(data)

        logger.info("All repositories have been processed for registry with id: %s", client_ecr.describe_registry()['registryId'])

    except (boto3.exceptions.Boto3Error, csv.Error) as e:
        # Log Boto3-specific errors
        logger.error("An error occurred while processing the registry for account %s in region %s: %s",
                     sts_client.get_caller_identity()["Account"], client_ecr.meta.region_name, str(e))

def get_image_summary(
        repo: str
) -> dict:
    """
    Retrieves a summary of images in a specified ECR repository.

    This function queries the specified Amazon ECR repository to gather summary statistics
    about the images it contains. The summary includes the total number of images, their
    combined size, and information about the last time an image was pulled.

    Args:
        repo (str): The name of the repository.

    Returns:
        dict: The summary data for images of the repo, including:
            - totalImages (int): Total number of images in the repository.
            - totalSize(MB) (float): Total size of all images in MB.
            - hasBeenPulled (bool): Whether any image has been pulled.
            - lastRecordedPullTime (datetime or None): Time of the last image pull, if any.
            - daysSinceLastPull (int or None): Days since the last image pull, if any.
            - monthlyStorageCost(USD) (float): Monthly storage cost in USD.

    Raises:
        boto3.exceptions.Boto3Error: If there's an error interacting with AWS ECR.
        Exception: For any unexpected errors during processing.
    """
    # Get ECR unit costs
    ecr_costs = get_ecr_unit_costs()

    try:
        # Initialize variables
        total_images = 0
        total_size = 0
        dt = pytz.utc.localize(datetime(1900, 1, 1, 12, 0, 0))
        day_diff = None
        flag = False
        response = client_ecr.describe_images(repositoryName=repo,maxResults=MAX_RESULTS)

        # Query ECR for image details
        while True:
            for i in response['imageDetails']:
                total_images += 1
                total_size = total_size + i['imageSizeInBytes']
                if 'lastRecordedPullTime' in i:
                    if i['lastRecordedPullTime'] > dt:
                        dt = i['lastRecordedPullTime']
                        flag = True

            # Check for more pages of results
            if 'nextToken' not in response:
                break
            response = client_ecr.describe_images(repositoryName=repo,nextToken=response['nextToken'], maxResults=MAX_RESULTS)

        # Calculate days since last pull
        if flag is False:
            dt = None
        else:
            day_diff = (datetime.now(pytz.UTC) - dt).days

        # Compile summary data
        summary = {'totalImages': total_images,
                   'totalSize(MB)': round(total_size / (1000**2),1),
                   'monthlyStorageCost(USD)': round(total_size * ecr_costs['price_per_unit'] / (1000**3),4),
                   'lastRecordedPullTime': dt,
                   'daysSinceLastPull': day_diff
                }

        logger.info("All images have been processed for repository: %s", repo)
        return summary

    except boto3.exceptions.Boto3Error as e:
        # Log Boto3-specific errors
        logger.error("A Boto3 error occurred while processing repository %s: %s", repo, str(e))
        return {'totalImages': 0, 'totalSize(MB)': 0, 'monthlyStorageCost(USD)': 0,
                'lastRecordedPullTime': None, 'daysSinceLastPull': None}

    except Exception as e:
        # Log any unexpected errors
        logger.error("An unexpected error occurred while processing repository %s: %s", repo, str(e))
        raise

def get_lifecycle_policy(
    repo: str
) -> dict:
    """
    Retrieves the lifecycle policy of a specified ECR repository.

    This function queries the specified repository to obtain its lifecycle policy text.
    If no policy is found, it returns a dictionary with a None value for the policy text.

    Args:
        repo (str): The name of the repository to query.

    Returns:
        dict: A dictionary containing the lifecycle policy text with the key 'lifecyclePolicyText'.
              If no policy is found, the value is None.

    Raises:
        boto3.exceptions.Boto3Error: If an error occurs while interacting with AWS ECR.
        Exception: For any unexpected errors during processing.
    """
    try:
        # Initialize the policy text
        text = None

        # Query ECR for lifecycle policy
        response = client_ecr.get_lifecycle_policy(repositoryName=repo)
        text = response['lifecyclePolicyText']
        lifecycle_policy = {'lifecyclePolicyText': text}

        logger.info("All lifecycle policies have been processed for repository: %s", repo)
        return lifecycle_policy

    except client_ecr.exceptions.LifecyclePolicyNotFoundException:
        # Handle case where no lifecycle policy is found
        lifecycle_policy = {'lifecyclePolicyText': text}
        logger.warning("No lifecycle policy found for repository: %s", repo)
        return lifecycle_policy

    except boto3.exceptions.Boto3Error as e:
        # Log Boto3-specific errors
        logger.error("A Boto3 error occurred while processing repository %s: %s", repo, str(e))
        return {'lifecyclePolicyText': None}
    except Exception as e:
        # Log any unexpected errors
        logger.error("An unexpected error occurred while processing repository %s: %s", repo, str(e))
        raise

def get_image_report(
        repo: str
)-> None:
    """
    Generates a detailed report for the images in a specified ECR repository.

    This function queries the specified repository to gather detailed information about each image,
    including tags, size, scan status, and more. The data is then written to a CSV file.

    Args:
        repo (str): The name of the repository to query.

    Raises:
        boto3.exceptions.Boto3Error: If an error occurs while interacting with AWS ECR.
        csv.Error: If an error occurs while writing to the CSV file.
    """
    # Define the columns for the CSV report
    IMAGE_REPORT_COLUMNS = [
        "repositoryName","imageTags","imagePushedAt","imageSize(MB)","imageScanStatus","imageScanCompletedAt",
        "findingSeverityCounts","lastRecordedPullTime","imageDigest","imageManifestMediaType"
    ]

    try:
        # Query ECR for image details
        response = client_ecr.describe_images(repositoryName=repo,maxResults=MAX_RESULTS)
        images = []
        while True:
            for i in response['imageDetails']:
                # Extract image details
                if 'lastRecordedPullTime' in i:
                    dt = i['lastRecordedPullTime']
                else:
                    dt = None

                if 'imageTags' in i:
                    tags = i['imageTags']
                else:
                    tags = None

                scan_status = None
                scan_completed_at = None
                finding_severity_counts = None

                # Check if image scan is complete and extract findings
                if 'imageScanStatus' in i:
                    scan_status = i['imageScanStatus']['status']
                    if i['imageScanStatus']['status'] == 'COMPLETE':
                        scan_completed_at = i['imageScanFindingsSummary']['imageScanCompletedAt'].strftime("%m/%d/%Y %H:%M")
                        finding_severity_counts = i['imageScanFindingsSummary']['findingSeverityCounts']

                # Compile image data
                image = {
                    'repositoryName': i['repositoryName'],
                    'imageTags': tags,
                    'imagePushedAt': i['imagePushedAt'].strftime("%m/%d/%Y %H:%M"),
                    'imageSize(MB)': round(i['imageSizeInBytes'] / (1000**2),1),
                    'imageScanStatus': scan_status,
                    'imageScanCompletedAt': scan_completed_at,
                    'findingSeverityCounts': finding_severity_counts,
                    'lastRecordedPullTime': dt,
                    'imageDigest': i['imageDigest'],
                    'imageManifestMediaType': i['imageManifestMediaType'],
                }
                images.append(image)

            # Check for more pages of results
            if 'nextToken' not in response:
                break
            response = client_ecr.describe_images(repositoryName=repo,nextToken=response['nextToken'], maxResults=MAX_RESULTS)
            continue

        if repo.find('/') != -1:
            repo = repo.replace('/', '_')

        # Write image data to CSV file
        with open('/data/'+repo+'_'+IMAGE_REPORT_FILE, mode='a', newline='', encoding='utf-8') as file:
        #with open(IMAGE_REPORT_FILE, mode='a', newline='') as file:            # This if for local tests of python code.
            writer = csv.DictWriter(file, fieldnames=IMAGE_REPORT_COLUMNS, delimiter='|')
            writer.writeheader()
            for data in images:
                data['imageSize(MB)'] = str(data['imageSize(MB)']).replace('.', decimal_separator)
                writer.writerow(data)

        logger.info("All images have been processed for repository: %s", repo)

    except (boto3.exceptions.Boto3Error, csv.Error) as e:
        # Log Boto3-specific errors
        logger.error("An error occurred while processing repository %s: %s", repo, str(e))

def get_ecr_unit_costs() -> dict:
    """
    Retrieves the unit costs for Amazon ECR service in the current region.

    Returns:
        dict: Dictionary containing:
            - description (str): The pricing description
            - price_per_unit (float): The price per unit for ECR storage in USD

    Raises:
        boto3.exceptions.Boto3Error: If there's an error accessing the AWS Pricing API
        KeyError: If the expected pricing data structure is not found
        ValueError: If there's an error parsing the price value
    """
    try:
        pricing = boto3.client('pricing')
        region = pricing.meta.region_name

        # Get the pricing data for ECR
        response = pricing.get_products(
            ServiceCode='AmazonECR',
            Filters=[
                {'Type': 'TERM_MATCH', 'Field': 'regionCode', 'Value': region}
            ]
        )

        # Access the pricing data from the response
        price_list = json.loads(response['PriceList'][0])
        on_demand_prices = list(price_list['terms']['OnDemand'].values())
        price_dimensions = list(on_demand_prices[0]['priceDimensions'].values())

        # Validate the response contains expected data
        if not price_dimensions:
            raise ValueError(f"No pricing data found for region {region}")

        # Return the pricing data
        return {
            'description': price_dimensions[0]['description'],
            'price_per_unit': float(price_dimensions[0]['pricePerUnit']['USD'])
        }

    except (boto3.exceptions.Boto3Error, KeyError, ValueError) as e:
        logger.error("Failed to retrieve ECR pricing: %s", str(e))
        return {'description': 'Error retrieving pricing', 'price_per_unit': 0.0}

if __name__ == '__main__':
    if report == 'registry':
        get_ecr_repo_cost_report()
    else:
        get_image_report(report)
