terraform {
  backend "s3" {
    bucket = "herbgoto-infrastructure-state"
    key    = "prometheus"
    region = "us-east-1"
  }
}