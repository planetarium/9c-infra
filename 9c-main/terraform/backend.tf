terraform {
  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/9c-main"
    region = "us-east-2"
  }
}
