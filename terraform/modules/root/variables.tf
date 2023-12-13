variable "name" {
  description = "general name for cluster related resources."
  default     = "common-9c-infra-name"
}

variable "create_vpc" {
  description = "boolean to create new VPC"
  default     = false
}

# variables for creating new VPC
variable "vpc_name" {
  description = "new VPC name"
  default     = "common-terraform-vpc-name"
}

variable "vpc_cidr_block" {
  description = "cidr block for new VPC"
  default     = "10.0.0.0/16"
}

# variables for using existing VPC
variable "vpc_id" {
  description = "VPC ID"
  default     = "vpc-0ca5c72f48fdd131b"
}

variable "public_subnet_ids" {
  description = "public subnet IDs for cluster related resources."
  default     = ["subnet-0ca96dde71e1769ec", "subnet-0cd61e38c9a58210d", "subnet-09af06d47e1c87153"]
}

variable "public_subnets" {
  description = "map {AZ = Cidr} for new public subnets"
  default = {
    "us-east-2a" = "10.0.0.0/20"
    "us-east-2b" = "10.0.16.0/20"
    "us-east-2c" = "10.0.32.0/20"
  }
}

variable "private_subnets" {
  description = "map {AZ = Cidr} for new private subnets"
  default = {
    "us-east-2a" = "10.0.128.0/20"
    "us-east-2b" = "10.0.144.0/20"
    "us-east-2c" = "10.0.160.0/20"
  }
}

# variables for node group

variable "node_groups" {
  description = "List of node group config"
  default = {
    "9c-sample" = {
      instance_types    = ["c5.large"]
      availability_zone = "us-east-2a"
      desired_size      = 10
      min_size          = 10
      max_size          = 20
      taints = []
    }
  }
}
variable "instance_types" {
  description = "node group instance sizes"
  default     = ["t3.large"]
}

variable "desired_size" {
  description = "node group desired size"
  default     = 10
}

variable "max_size" {
  description = "node group max size"
  default     = 20
}

variable "min_size" {
  description = "node group min size"
  default     = 10
}

variable "addon_versions" {
  description = "List of Addon versions"
  default     = {
    "coredns"            = "v1.8.7-eksbuild.1"
    "kube-proxy"         = "v1.22.6-eksbuild.1"
    "vpc_cni"            = "v1.11.0-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.24.0-eksbuild.1"
  }
}

variable "loki_bucket" {
  description = "Loki's s3 bucket"

  default = "loki-dev.planetariumhq.com"
}