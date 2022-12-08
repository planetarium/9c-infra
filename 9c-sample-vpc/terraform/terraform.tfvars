# eks cluster
name = "9c-sample-vpc"

create_vpc = true

# new vpc
vpc_name       = "9c-sample-vpc"
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
  "9c-sample-vpc" = {
    instance_types    = ["c5.large"]
    availability_zone = "us-east-2a"
    desired_size      = 10
    min_size          = 10
    max_size          = 20
  }
}
