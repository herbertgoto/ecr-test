terraform {
  backend "s3" {
    bucket = "herbgoto-infrastructure-state"
    key    = "vpc-config"
    region = "us-east-1"
  }
}