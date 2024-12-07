terraform {
  backend "s3" {
    bucket = "herbgoto-infrastructure-state"
    key    = "grafana"
    region = "us-east-1"
  }
}