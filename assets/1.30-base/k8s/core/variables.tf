variable "cluster_version" {
  type        = string
  description = "Version of Kubernetes for eks"
  default     = "1.30"
}

variable "private_subnets_ids" {
  description = "Private subnets ids for the new cluster"
  default     = ["subnet-0b1f3d5d99097bb25", "subnet-05244cdd1693288f9"]
}

variable "private_subnets_id_workers" {
  description = "Private subnets ids for the new cluster"
  default     =  ["subnet-0b1f3d5d99097bb25", "subnet-05244cdd1693288f9"]
}

### Networking variables
variable "vpc_id" {
  default = "vpc-0bb0bc1ebe4d949bc"
}

### AWS Load Balancer Controller version
variable "aws_lb_controller" {
  default = "v2.10.1"
}