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
      desired_size      = 5
      min_size          = 0
      max_size          = 5
	  capacity_type     = "SPOT"
    }
    "9c-sample-r6g_xl_2c" = {
      instance_types    = ["r6g.xlarge"]
      availability_zone = "us-east-2c"
      desired_size      = 5
      min_size          = 0
      max_size          = 10
	  capacity_type     = "SPOT"
      ami_type          = "AL2_ARM_64"
    }
  }


  addon_versions = {
    "coredns"            = "v1.10.1-eksbuild.1"
    "kube-proxy"         = "v1.27.1-eksbuild.1"
    "vpc_cni"            = "v1.12.6-eksbuild.2"
    "aws_ebs_csi_driver" = "v1.17.0-eksbuild.1"
  }
}
