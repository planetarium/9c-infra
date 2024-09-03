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
    "9c-internal-c5_4xl_2c" = {
      instance_types    = ["c5d.4xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 0
      min_size          = 0
      max_size          = 1
    }

    "9c-internal-m5d_l_2c" = {
      instance_types    = ["m5d.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 0
      min_size          = 0
      max_size          = 20
    }

    "9c-internal-m5d_2xl_2c" = {
      instance_types    = ["m5d.2xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 0
      min_size          = 0
      max_size          = 5
    }

    "9c-internal-m5d_xl_2c" = {
      instance_types    = ["m5d.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 5
      min_size          = 5
      max_size          = 16
    }

    "9c-internal-m5_xl_2c_ondemand" = {
      instance_types    = ["m5.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 10
    }

    "9c-internal-m7g_2xl_2c" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 2
      min_size          = 2
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-internal-r6g_l_2c" = {
      instance_types    = ["r6g.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 0
      min_size          = 0
      max_size          = 25
      ami_type          = "AL2_ARM_64"
    }


    "9c-internal-r6g_xl_2c" = {
      instance_types    = ["r6g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 5
      min_size          = 5
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-internal-c7g_4xl_2c" = {
      instance_types    = ["c7g.4xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "SPOT"
      desired_size      = 0
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
    }

    "9c-internal-ondemand-r7g_l_2c" = {
      instance_types    = ["r7g.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 6
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-internal-ondemand-r7g_xl_2c" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-internal-t3_medium" = {
      instance_types    = ["t3.medium"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 1
    }

    "heimdall-preview-r7g_l_2c" = {
      instance_types    = ["r7g.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
    }

    "9c-preview-ondemand-r7g_l_2c" = {
      instance_types    = ["r7g.large"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-preview-ondemand-r7g_xl_2c" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
    }

    "9c-preview-m5_xl_2c_ondemand" = {
      instance_types    = ["m5.xlarge"]
      availability_zone = "us-east-2c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 10
    }
  }
}