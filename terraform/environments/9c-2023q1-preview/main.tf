terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 0.13.0"

  backend "s3" {
    bucket = "terraform-eks-backend"
    key    = "eks/9c-2023q1-preview"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-2023q1-preview"

  create_vpc = false

  # node group
  node_groups = {
    "9c-2023q1-preview-c5_l_2c" = {
      instance_types    = ["c5.large"]
      availability_zone = "us-east-2c"
      desired_size      = 10
      min_size          = 0
      max_size          = 10
    }
  }
}
