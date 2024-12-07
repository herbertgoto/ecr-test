terraform {
  backend "s3" {
    bucket = "herbgoto-infrastructure-state"
    key    = "eks-config"
    region = "us-east-1"
  }
}