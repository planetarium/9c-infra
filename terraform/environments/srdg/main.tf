terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 1.3.6"

  backend "s3" {
    bucket = "srdg-tfstates"
    key    = "eks/srdg"
    region = "ap-northeast-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "srdg"

  create_vpc = true

  nat_availability_zone = "ap-northeast-2c"

  addon_versions = {
    "coredns"            = "v1.10.1-eksbuild.6"
    "kube-proxy"         = "v1.28.1-eksbuild.1"
    "vpc_cni"            = "v1.15.4-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.26.0-eksbuild.1"
  }

  loki_bucket = "loki.planetariumhq.com"

  # new vpc
  vpc_name       = "srdg"
  vpc_cidr_block = "172.20.0.0/16"
  public_subnets = {
    "ap-northeast-2a" = "172.20.0.0/20"
    "ap-northeast-2c" = "172.20.32.0/20"
  }
  private_subnets = {
    "ap-northeast-2a" = "172.20.128.0/20"
    "ap-northeast-2c" = "172.20.160.0/20"
  }

  # node group
  node_groups = {
    "srdg-m5_l_2c" = {
      instance_types    = ["m5.large"]
      availability_zone = "ap-northeast-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 12
    }
  }
}
