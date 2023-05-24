# eks cluster
name = "9c-internal-mead"

create_vpc = true

# new vpc
vpc_name       = "9c-internal-mead"
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
  "9c-internal-v2-c5_4xl_2c" = {
    instance_types    = ["c5d.4xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 0
    min_size          = 0
    max_size          = 1
  }

  "9c-internal-v2-m5d_l_2c" = {
    instance_types    = ["m5d.large"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 3
    min_size          = 0
    max_size          = 10
  }

  "9c-internal-v2-m5d_2xl_2c" = {
    instance_types    = ["m5d.2xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 0
    min_size          = 0
    max_size          = 5
  }

  "9c-internal-v2-m5d_xl_2c" = {
    instance_types    = ["m5d.xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 0
    min_size          = 0
    max_size          = 15
  }

  "9c-internal-v2-r6g_l_2c" = {
    instance_types    = ["r6g.large"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 5
    min_size          = 0
    max_size          = 15
    ami_type          = "AL2_ARM_64"
  }

  "9c-internal-v2-r6g_xl_2c" = {
    instance_types    = ["r6g.xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 0
    min_size          = 0
    max_size          = 15
    ami_type          = "AL2_ARM_64"
  }
}
