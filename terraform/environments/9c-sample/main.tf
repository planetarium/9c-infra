terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 0.13.0"

  backend "s3" {
    bucket = "terraform-eks-backend"
    key    = "eks/9c-sample"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-sample"

  create_vpc = false

  # node group
  node_groups = {
    "9c-sample-c5_l_2c" = {
      instance_types    = ["c5.large"]
      availability_zone = "us-east-2c"
      desired_size      = 10
      min_size          = 0
      max_size          = 10
    }
  }

  addon_versions = {
    "coredns"            = "v1.8.7-eksbuild.3"
    "kube-proxy"         = "v1.24.7-eksbuild.2"
    "vpc_cni"            = "v1.11.4-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.6.1-eksbuild.1"
  }
}
