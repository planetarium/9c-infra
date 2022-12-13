terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 0.13.0"

  backend "s3" {
    bucket = "terraform-eks-backend"
    key    = "eks/9c-internal"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../common/terraform"

  # eks cluster
  name = "9c-internal"

  create_vpc = false
}
