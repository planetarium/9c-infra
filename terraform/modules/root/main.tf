terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "> 4.0.0"
    }
  }
}

variable "availability_zone" {
  type    = string
  default = "us-east-2c"
}
