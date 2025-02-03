module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "10.0.0"

  project_id   = var.project_id
  network_name = "${var.network}-${var.env_name}"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name           = "subnet-01"
      subnet_ip             = var.subnet_ip
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_flow_logs      = true
      description           = "For private subnet"
    }
  ]

  # Secondary ranges for Pods and Services
  secondary_ranges = {
    subnet-01 = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = "10.20.0.0/16"
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = "10.21.0.0/16"
      }
    ]
  }
}
