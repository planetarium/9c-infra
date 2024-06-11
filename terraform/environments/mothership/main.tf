terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 1.3.6"

  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/mothership"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "mothership"

  create_vpc = true

  addon_versions = {
    "coredns"            = "v1.11.1-eksbuild.4"
    "kube-proxy"         = "v1.29.0-eksbuild.1"
    "vpc_cni"            = "v1.16.0-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.28.0-eksbuild.1"
  }

  loki_bucket = "loki-mothership.planetariumhq.com"

  # new vpc
  vpc_name       = "mothership"
  vpc_cidr_block = "10.0.0.0/16"
  public_subnets = {
    "us-east-2a" = "10.0.0.0/20"
    "us-east-2b" = "10.0.16.0/20"
    "us-east-2c" = "10.0.32.0/20"
  }
  private_subnets = {
    "us-east-2a" = "10.0.128.0/20"
    "us-east-2b" = "10.0.144.0/20"
    "us-east-2c" = "10.0.160.0/20"
  }

  # node group
  node_groups = {
    "mothership-m7g_l_2c" = {
      instance_types    = ["m7g.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 5
      ami_type          = "AL2_ARM_64"
    }
    "mothership-r7g_xl_2c" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 5
      ami_type          = "AL2_ARM_64"
    }
    "mothership-r7a_l_2c" = {
      instance_types    = ["r7a.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 5
      ami_type          = "AL2_x86_64"
    }
  }
}
