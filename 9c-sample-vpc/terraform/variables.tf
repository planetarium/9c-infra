variable "name" {
  description = "general name for cluster related resources."
  default     = "9c-vpc"
}

variable "create_vpc" {
  description = "boolean to create new VPC"
  default     = false
}

# variables for creating new VPC
variable "vpc_name" {
  description = "new VPC name"
}

variable "vpc_cidr_block" {
  description = "cidr block for new VPC"
}

variable "public_subnet_cidr_blocks" {
  type        = list(string)
  description = "cidr block list for new public subnets"
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  description = "cidr block list for new private subnets"
}

variable "availability_zones" {
  type        = list(string)
  description = "availability zones"
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

# variables for using existing VPC
variable "vpc_id" {
  description = "VPC ID"
  default     = "vpc-0ca5c72f48fdd131b"
}

variable "public_subnets" {
  description = "public subnet IDs for cluster related resources."
  default     = ["subnet-0ca96dde71e1769ec", "subnet-0cd61e38c9a58210d", "subnet-09af06d47e1c87153"]
}

# variables for node group
variable "instance_types" {
  description = "node group instance sizes"
  default     = ["t3.large"]
}

variable "desired_size" {
  description = "node group desired size"
  default     = 10
}

variable "max_size" {
  description = "node group max size"
  default     = 20
}

variable "min_size" {
  description = "node group min size"
  default     = 10
}
