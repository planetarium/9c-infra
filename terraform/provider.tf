provider "aws" {
  region = var.region
  profile = "planetarium"
}

module "network" {
  source = "./modules/network"
  region = var.region
}
