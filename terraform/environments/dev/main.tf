terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 1.3.6"

  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/9c-dev-v2"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-dev-v2"

  create_vpc = true

  loki_bucket = "loki-9c-dev-v2.planetariumhq.com"

  # new vpc
  vpc_name       = "9c-dev"
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
  node_groups = {}
}
