module "vpc" {
  source = "../../modules/vpc"

  project_id               = var.project_id
  env_name                 = var.env_name
  network                  = var.network
  subnet_ip                = var.subnet_ip
  region                   = var.region
  ip_range_pods_name       = var.ip_range_pods_name
  ip_range_services_name   = var.ip_range_services_name
}

module "gke" {
  source = "../../modules/gke"

  project_id             = var.project_id
  cluster_name           = var.cluster_name
  region                 = var.region
  zones                  = var.zones
  network_name           = module.vpc.network_name
  subnet_name            = module.vpc.subnets_names[0]
  ip_range_pods_name     = var.ip_range_pods_name
  ip_range_services_name = var.ip_range_services_name

  node_machine_type = var.node_machine_type
  node_min_count    = var.node_min_count
  node_max_count    = var.node_max_count
}
