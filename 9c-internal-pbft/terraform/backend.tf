terraform {
  backend "s3" {
    bucket = "9c-tfstates"
    key    = "eks/9c-internal"
    region = "us-east-2"
  }
}
