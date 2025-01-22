##############################################################################
# Terraform / Provider 설정
##############################################################################
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }

  required_version = ">= 1.3.0"

  # AWS S3 대신, GCS backend 예시 (원하는 곳에 맞춰 수정)
  backend "gcs" {
    bucket = "my-terraform-states"
    prefix = "gcp-vpc-states"
  }
}

provider "google" {
  project = var.project_id
  region  = var.default_region
  # credentials = file("...")  // 필요한 경우
}

##############################################################################
# 변수 가정
##############################################################################
variable "create_vpc" {
  type    = bool
  default = true
}

variable "vpc_name" {
  type    = string
  default = "my-vpc"
}

variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type = map(string)
  # 예: { "us-east1" = "10.0.0.0/20", "us-east1" = "10.0.16.0/20" } 식 중복 리전
  default = {}
}

variable "private_subnets" {
  type = map(string)
  # 예: { "us-east1" = "10.0.128.0/20", "us-east1" = "10.0.144.0/20" }
  default = {}
}

variable "project_id" {
  type    = string
  default = "my-gcp-project"
}

variable "default_region" {
  type    = string
  default = "us-east1"
}


##############################################################################
# 2. VPC 생성 (AWS VPC -> google_compute_network)
##############################################################################
resource "google_compute_network" "default" {
  count                    = var.create_vpc ? 1 : 0
  name                     = "vpc-${var.vpc_name}"
  auto_create_subnetworks  = false
  description              = "Equivalent of AWS VPC with CIDR ${var.vpc_cidr_block}"
  project                  = var.project_id
  routing_mode             = "REGIONAL" # "GLOBAL"도 가능하나 일반적으로 REGIONAL
}

##############################################################################
# 3. 서브넷 생성 (AWS Subnet -> google_compute_subnetwork)
#    - GCP는 region 단위.
##############################################################################
# 퍼블릭 서브넷
resource "google_compute_subnetwork" "public" {
  # AWS 코드처럼 for_each 활용
  for_each = {
    for region, cidr in var.public_subnets : region => cidr
    if var.create_vpc
  }

  name                  = "public-${each.key}-${var.vpc_name}"
  ip_cidr_range         = each.value
  region                = each.key
  network               = google_compute_network.default[0].self_link
  project               = var.project_id
  # GCP에는 'map_public_ip_on_launch' 개념이 없고,
  # VM 인스턴스 생성 시 external IP 할당 여부로 퍼블릭 접근이 결정됨
  # public_subnet이라는 의미만 태그 정도로 표기
  description           = "Public subnetwork in region ${each.key} - CIDR ${each.value}"

  # AWS의 enable_dns_hostnames, assign_generated_ipv6_cidr_block 등은
  # GCP에서는 별도 설정 방식(IPv6 서브넷)을 따름 (여기서는 생략).
}

# 프라이빗 서브넷
resource "google_compute_subnetwork" "private" {
  for_each = {
    for region, cidr in var.private_subnets : region => cidr
    if var.create_vpc
  }

  name        = "private-${each.key}-${var.vpc_name}"
  ip_cidr_range = each.value
  region      = each.key
  network     = google_compute_network.default[0].self_link
  project     = var.project_id

  # 프라이빗에서 구글 API 접근(예: GCS, BigQuery)을 사설 IP로 사용
  # 하려면 private_ip_google_access = true
  private_ip_google_access = true

  description = "Private subnetwork in region ${each.key} - CIDR ${each.value}"
}

##############################################################################
# 4. 인터넷 연결 (AWS Internet Gateway -> GCP는 별도 리소스 없음)
#    GCP는 기본적으로 0.0.0.0/0 라우트를 만들 수 있지만, 
#    별도 internet_gateway 리소스는 없습니다.
##############################################################################
# 만약 VPC에 기본 0.0.0.0/0 라우트가 없다면 아래처럼 직접 생성 가능
# (기본 라우트는 자동으로 생기는 경우가 많아, 필요 시만 추가)
resource "google_compute_route" "default_internet_route" {
  count = var.create_vpc ? 1 : 0

  name            = "igw-${var.vpc_name}"
  network         = google_compute_network.default[0].self_link
  destination_range = "0.0.0.0/0"
  next_hop_internet = true
  project         = var.project_id

  # 우선순위(낮을수록 우선)
  priority        = 1000
}

##############################################################################
# 5. Cloud NAT (AWS NAT Gateway -> google_compute_router + google_compute_router_nat)
##############################################################################
# 5-1. NAT용 외부 IP (AWS EIP -> google_compute_address)
resource "google_compute_address" "nat" {
  count   = var.create_vpc ? 1 : 0
  name    = "nat-ip-${var.vpc_name}"
  project = var.project_id
  region  = var.default_region
}

# 5-2. Cloud Router (NAT 연동 필요)
resource "google_compute_router" "nat_router" {
  count   = var.create_vpc ? 1 : 0
  name    = "nat-router-${var.vpc_name}"
  network = google_compute_network.default[0].self_link
  project = var.project_id
  region  = var.default_region
}

# 5-3. 실제 NAT 설정 (AWS NAT Gateway처럼 사설 서브넷 -> 외부 인터넷)
resource "google_compute_router_nat" "nat" {
  count   = var.create_vpc ? 1 : 0
  name    = "nat-gw-${var.vpc_name}"
  router  = google_compute_router.nat_router[0].name
  project = var.project_id
  region  = var.default_region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips               = [google_compute_address.nat[0].self_link]

  # 어떤 서브넷을 NAT로 연결할지 지정
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # private 서브넷들에 대해 NAT 적용
  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                   = subnetwork.value.self_link
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  # 필요 시 NAT 타임아웃 or 포트 할당 방식 등 추가 설정 가능
  min_ports_per_vm = 128
}

##############################################################################
# 참고: GCP에서 서브넷별 “라우트 테이블”을 직접 만들 필요가 없습니다.
#       public/private 구분은 VM에 외부 IP를 할당하느냐(=퍼블릭),
#       혹은 Cloud NAT를 이용하느냐(=프라이빗)로 결정됩니다.
##############################################################################
