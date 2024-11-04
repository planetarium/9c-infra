terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 1.3.6"

  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/9c-internal-v2"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-internal-v2"

  create_vpc = true

  addon_versions = {
    "coredns"            = "v1.10.1-eksbuild.15"
    "kube-proxy"         = "v1.28.12-eksbuild.9"
    "vpc_cni"            = "v1.18.5-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.36.0-eksbuild.1"
  }

  # new vpc
  vpc_name       = "9c-internal"
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
    "heimdall-spot_2c" = {
      instance_types    = ["r7g.large", "r6g.large", "m8g.xlarge", "m7g.xlarge", "m6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "heimdall-preview-spot_2c" = {
      instance_types    = ["r7g.large", "r6g.large", "m8g.xlarge", "m7g.xlarge", "m6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-internal-spot_2c" = {
      instance_types    = ["r7g.large", "r6g.large", "m8g.xlarge", "m7g.xlarge", "m6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "odin-spot_2c" = {
      instance_types    = ["r7g.large", "r6g.large", "m8g.xlarge", "m7g.xlarge", "m6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "odin-spot_xl_2c" = {
      instance_types    = ["r7g.xlarge", "r6g.xlarge", "m8g.2xlarge", "m7g.2xlarge", "m6g.2xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "odin-preview-spot_2c" = {
      instance_types    = ["r7g.large", "r6g.large", "m8g.xlarge", "m7g.xlarge", "m6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "thor-spot_2c" = {
      instance_types    = ["r7g.large", "r6g.large", "m8g.xlarge", "m7g.xlarge", "m6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }
  }
}
