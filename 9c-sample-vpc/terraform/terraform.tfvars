# eks cluster
name = "9c-sample-vpc"

create_vpc = true

# new vpc
vpc_name                   = "9c-sample-vpc"
vpc_cidr_block             = "10.0.0.0/16"
public_subnet_cidr_blocks  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
private_subnet_cidr_blocks = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]


# node group
instance_types = ["c5.large"]
desired_size   = 10
max_size       = 20
min_size       = 10
