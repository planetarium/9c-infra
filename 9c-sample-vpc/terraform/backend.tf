terraform {
  backend "s3" {
    bucket = "terraform-eks-backend"
    key    = "eks/9c-vpc"
    region = "us-east-2"
  }
}
