# eks cluster
name = "9c-internal-v2"

create_vpc = true

# new vpc
vpc_name       = "9c-internal"
vpc_cidr_block = "10.0.0.0/16"
public_subnets = {
  "us-east-2a" = "10.0.0.0/20"
  "us-east-2b" = "10.0.16.0/20"
  "us-east-2c" = "10.0.32.0/20" }
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
    desired_size      = 4
    min_size          = 0
    max_size          = 15
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
    desired_size      = 0
    min_size          = 0
    max_size          = 16
  }

  "9c-internal-m7g_2xl_2c" = {
    instance_types    = ["m7g.2xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 1
    min_size          = 0
    max_size          = 1
    ami_type          = "AL2_ARM_64"
  }

  "9c-internal-r6g_l_2c" = {
    instance_types    = ["r6g.large"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 5
    min_size          = 0
    max_size          = 15
    ami_type          = "AL2_ARM_64"
  }


  "9c-internal-r6g_xl_2c" = {
    instance_types    = ["r6g.xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 5
    min_size          = 0
    max_size          = 15
    ami_type          = "AL2_ARM_64"
  }

  "9c-internal-c7g_4xl_2c" = {
    instance_types    = ["c7g.4xlarge"]
    availability_zone = "us-east-2c"
    capacity_type     = "SPOT"
    desired_size      = 1
    min_size          = 0
    max_size          = 1
    ami_type          = "AL2_ARM_64"
  }

  "9c-internal-ondemand-r6g_l_2c" = {
    instance_types    = ["r6g.large"]
    availability_zone = "us-east-2c"
    capacity_type     = "ON_DEMAND"
    desired_size      = 5
    min_size          = 0
    max_size          = 15
    ami_type          = "AL2_ARM_64"
  }

  "heimdall-internal-r7g_l_2c" = {
    instance_types    = ["r7g.large"]
    availability_zone = "us-east-2c"
    capacity_type     = "ON_DEMAND"
    desired_size      = 5
    min_size          = 5
    max_size          = 10
    ami_type          = "AL2_ARM_64"
  }
}
