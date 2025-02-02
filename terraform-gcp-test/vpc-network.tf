# vpc-network.tf
# VPC와 서브넷을 프로비저닝한다.
module "vpc" {
  source       = "terraform-google-modules/network/google"
  version      = "10.0.0"
  project_id   = var.project_id
  network_name = "${var.network}-${var.env_name}"
  routing_mode = "GLOBAL"
  subnets = [
    {
      subnet_name           = "subnet-01"
      subnet_ip             = "10.10.20.0/24"
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_flow_logs      = true
      description           = "For private subnet"
    }
  ]
  # 클러스터 내부의 Pods와 Services에 IP 주소를 할당하기 위한 추가적인 IP 범위
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
