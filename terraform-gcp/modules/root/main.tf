terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

# GCP에서 Cloud NAT는 '리전' 단위로 설정되므로,
# 'nat_availability_zone' 대신 'nat_region' 변수로 명명하는 것이 일반적입니다.
variable "nat_region" {
  type    = string
  default = "us-east1"
}