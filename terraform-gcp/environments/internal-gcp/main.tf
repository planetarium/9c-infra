##############################################################################
# 1. Terraform 및 Provider 설정
##############################################################################

terraform {
  required_version = ">= 1.3.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }

  # AWS S3 대신 GCS(Google Cloud Storage)를 backend로 사용
  backend "gcs" {
    bucket = "9c-tfstates"         # 기존 예시처럼 동일 버킷 이름 가정
    prefix = "gke/9c-internal-v2"  # 예: eks/9c-internal-v2 -> gke/9c-internal-v2
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  # credentials  = file("path/to/credentials.json") 
  # 또는 애플리케이션 기본 자격증명(Application Default Credentials) 사용
}

##############################################################################
# 2. VPC (네트워크) 및 서브넷 설정
##############################################################################

# 기존 "create_vpc = true" 및 "vpc_name = 9c-internal", "vpc_cidr_block = 10.0.0.0/16"
# AWS에서는 AZ별 퍼블릭/프라이빗 서브넷이 있었지만, GCP에서는 리전 단위 Subnetwork만 생성 예시
##############################################################################

resource "google_compute_network" "vpc" {
  name                    = "9c-internal"
  auto_create_subnetworks = false
}

# 하나의 큰 서브넷 혹은 여러 개로 나눌 수도 있음
# 여기서는 AWS에서 사용한 CIDR 중 하나(10.0.0.0/16)를 그대로 사용
resource "google_compute_subnetwork" "main_subnet" {
  name                  = "9c-internal-subnet"
  ip_cidr_range         = "10.0.0.0/16"
  region                = var.region
  network               = google_compute_network.vpc.self_link
  private_ip_google_access = true
}

##############################################################################
# 3. GKE 클러스터 설정
##############################################################################

# AWS EKS -> GKE 로 매핑
# - EKS의 addon_versions(VPC CNI, CoreDNS 등)는 GKE에서 자동 제공 혹은 내장
# - EKS의 퍼블릭/프라이빗 엔드포인트 설정은 GKE private_cluster_config로 대응 가능

resource "google_container_cluster" "gke_cluster" {
  name     = "9c-internal-cluster"
  region   = var.region
  project  = var.project_id

  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.main_subnet.self_link

  # GKE의 VPC Native 모드(= Alias IP) 사용 권장
  ip_allocation_policy {
    use_ip_aliases = true
  }

  # 예) Private Cluster 로 쓰고 싶다면 (선택사항)
  # private_cluster_config {
  #   enable_private_endpoint = false
  #   enable_private_nodes    = true
  #   master_ipv4_cidr_block  = "172.16.0.0/28"
  # }

  # 원하는 GKE 버전 채널 (예: STABLE, REGULAR, RAPID)
  release_channel {
    channel = "STABLE"
  }

  # 일부 Add-on 설정 (예: GCE PD CSI Driver)
  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
}

##############################################################################
# 4. Node Pool 설정 (EKS의 node_groups -> GKE node pools)
##############################################################################
# - AWS SPOT → GCP Preemptible
# - AWS ARM Instance Types(r7g, m6g 등) → GCP Machine Types(e2, n2d, t2d 등)로 매핑
##############################################################################

# 예시: 작은 스펙(r7g.large 등)에 해당 -> t2d-standard-2(2vCPU, 4GB 메모리 등)
resource "google_container_node_pool" "heimdall_spot_2c" {
  name       = "heimdall-spot-2c"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.gke_cluster.name

  node_config {
    preemptible  = true                      # AWS SPOT 대응
    machine_type = "t2d-standard-2"          # AWS r7g.large 대체 예시
    # image_type  = "COS_CONTAINERD"         # OS 이미지 선택 가능
    # service_account = "..."                # 노드에 할당할 GCP SA
    # labels, taints 등 추가 가능
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 15
  }

  initial_node_count = 1
}


resource "google_container_node_pool" "odin_spot_2c" {
  name       = "odin-spot-2c"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.gke_cluster.name

  node_config {
    preemptible  = true
    machine_type = "t2d-standard-2"
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 15
  }

  initial_node_count = 1
}


resource "google_container_node_pool" "thor_spot_2c" {
  name       = "thor-spot-2c"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.gke_cluster.name

  node_config {
    preemptible  = true
    machine_type = "t2d-standard-2"
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 15
  }

  initial_node_count = 1
}

##############################################################################
# 5. 변수 예시 (variables.tf)
##############################################################################
variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  description = "GCP Region"
  default     = "us-east1"  # 예시
}