terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 1.3.6"

  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/9c-onboarding-mizuki"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-onboarding-mizuki"

  create_vpc = true

  loki_bucket = "loki-9c-onboarding-mizuki.planetariumhq.com"

  # new vpc
  vpc_name       = "9c-onboarding-mizuki"
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

  addon_versions = {
    "coredns"            = "v1.10.1-eksbuild.2"
    "kube-proxy"         = "v1.28.1-eksbuild.1"
    "vpc_cni"            = "v1.14.1-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.24.0-eksbuild.1"
  }

  # node group
  node_groups = {
    "onboarding-mizuki-m5d_l_2c" = {
      instance_types    = ["m5d.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 20
    }

    "onboarding-mizuki-m7g_2xl_2c" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 5
      min_size          = 2
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "onboarding-mizuki-t3_medium" = {
      instance_types    = ["t3.medium"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 1
    }
  }
}
