terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 1.3.6"

  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/9c-main-apse1"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-main-apse1"

  create_vpc = true

  nat_availability_zone = "ap-southeast-1c"

  addon_versions = {
    "coredns"            = "v1.11.1-eksbuild.4"
    "kube-proxy"         = "v1.29.0-eksbuild.1"
    "vpc_cni"            = "v1.16.0-eksbuild.1"
    "aws_ebs_csi_driver" = "v1.28.0-eksbuild.1"
  }

  loki_bucket = "loki.planetariumhq.com"

  # new vpc
  vpc_name       = "9c-main-apse1"
  vpc_cidr_block = "10.0.0.0/16"
  public_subnets = {
    "ap-southeast-1a" = "10.0.0.0/20"
    "ap-southeast-1b" = "10.0.16.0/20"
    "ap-southeast-1c" = "10.0.32.0/20"
  }
  private_subnets = {
    "ap-southeast-1a" = "10.0.128.0/20"
    "ap-southeast-1b" = "10.0.144.0/20"
    "ap-southeast-1c" = "10.0.160.0/20"
  }

  # node group
  node_groups = {
    "9c-main-apse1-m5_l_2c" = {
      instance_types    = ["m5.large"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 12
    }

    "9c-main-apse1-r7g_xl_2c" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 2
      ami_type          = "AL2_ARM_64"
    }

    "9c-main-apse1-m7g_xl_2c" = {
      instance_types    = ["m7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 6
      ami_type          = "AL2_ARM_64"
    }

    "9c-main-apse1-m7g_2xl_2c_test" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 1
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "9c-main-apse1-r7g_2xl_2c_test" = {
      instance_types    = ["r7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 3
      min_size          = 3
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "9c-main-apse1-r7g_2xl_2c" = {
      instance_types    = ["r7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
    }

    "9c-main-apse1-c7g_4xl_2c_test" = {
      instance_types    = ["c7g.4xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "9c-main-apse1-r7g_xl_2c_validator" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "validator-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "9c-main-apse1-m7g_2xl_2c_validator" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 4
      min_size          = 4
      max_size          = 10
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "validator-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "9c-main-apse1-r6g_xl_2c" = {
      instance_types    = ["r6g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 7
      min_size          = 0
      max_size          = 20
      ami_type          = "AL2_ARM_64"
    }

    "9c-main-apse1-t3_medium" = {
      instance_types    = ["t3.medium"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 1
    }

    "9c-main-apse1-spot" = {
      instance_types    = ["r7g.xlarge", "m7g.2xlarge", "r6g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "SPOT"
      desired_size      = 3
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "heimdall-m5_l_2c" = {
      instance_types    = ["m5.large"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 12
    }

    "heimdall-r7g_xl_2c" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 5
      ami_type          = "AL2_ARM_64"
    }

    "heimdall-m7g_xl_2c" = {
      instance_types    = ["m7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 0
      max_size          = 6
      ami_type          = "AL2_ARM_64"
    }

    "heimdall-m7g_2xl_2c_test" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 1
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "heimdall-r7g_2xl_2c_test" = {
      instance_types    = ["r7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 5
      min_size          = 5
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "heimdall-m7g_4xl_2c_test" = {
      instance_types    = ["m7g.4xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "heimdall-r7g_2xl_2c" = {
      instance_types    = ["r7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 2
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
    }

    "heimdall-m7g_2xl_2c_validator" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 6
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "validator-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "heimdall-r7g_xl_2c_validator" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 1
      min_size          = 1
      max_size          = 6
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "validator-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "heimdall-2c_spot" = {
      instance_types    = ["r7g.xlarge", "m7g.2xlarge", "r6g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "SPOT"
      desired_size      = 3
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "idun-m5_l_2c" = {
      instance_types    = ["m5.large"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 12
    }

    "idun-r7g_xl_2c" = {
      instance_types    = ["r7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 10
      ami_type          = "AL2_ARM_64"
    }

    "idun-m7g_xl_2c" = {
      instance_types    = ["m7g.xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 6
      ami_type          = "AL2_ARM_64"
    }

    "idun-m7g_2xl_2c_test" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 15
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "remote-headless-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "idun-m7g_2xl_2c_validator" = {
      instance_types    = ["m7g.2xlarge"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "ON_DEMAND"
      desired_size      = 0
      min_size          = 0
      max_size          = 6
      ami_type          = "AL2_ARM_64"
      disk_size         = 50
      taints = [{
        key    = "dedicated"
        value  = "validator-test"
        effect = "NO_SCHEDULE"
      }]
    }

    "general-t3_medium" = {
      instance_types    = ["t3.medium"]
      availability_zone = "ap-southeast-1c"
      capacity_type     = "SPOT"
      desired_size      = 1
      min_size          = 0
      max_size          = 1
    }
  }
}
