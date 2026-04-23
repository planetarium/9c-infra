terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4"
    }
  }
  required_version = ">= 1.3.6"

  # Isolated state for pt6-only resources (IAM OIDC + role + policy).
  # Keeps pt6 changes independent from the 9c-main-v2 EKS state, which
  # currently has drift (cluster not present in AWS).
  backend "s3" {
    bucket = "9c-tfstates"
    key    = "pt6/oidc-irsa"
    region = "us-east-2"
  }
}

provider "aws" {
  region = "us-east-2"
}
