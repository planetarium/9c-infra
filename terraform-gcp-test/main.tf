# main.tf
# GKE 클러스터와, 별도로 관리되는 노드 풀을 생성한다.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

resource "google_service_account" "default" {
  # google_service_account 리소스의 account_id에는 서비스 계정의
  # 전체 이메일 주소가 아니라 고유 ID 부분만 포함해야 한다.
  account_id   = "k8s-standard-architecture"
  project      = var.project_id
  display_name = "K8s Standard Architecture Service Account"
  description  = "Service account for K8s standard architecture"
}

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version                    = "35.0.1"
  project_id                 = var.project_id
  name                       = var.cluster_name
  region                     = var.region
  zones                      = var.zones
  network                    = module.vpc.network_name
  subnetwork                 = module.vpc.subnets_names[0]
  ip_range_pods              = var.ip_range_pods_name
  ip_range_services          = var.ip_range_services_name
  http_load_balancing        = true
  network_policy             = true
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  enable_private_endpoint    = false
  enable_private_nodes       = true
  master_ipv4_cidr_block     = "10.0.0.0/28"
  deletion_protection        = false 
  # Terraform 등 다른 방법으로 클러스터가 삭제되는 것을 허용하지 않는다면 true로 설정

  node_pools = [
    {
      name            = "default-node-pool"
      machine_type    = "e2-standard-4"
      node_locations  = "asia-northeast3-b,asia-northeast3-c"
      min_count       = 2
      max_count       = 5
      disk_size_gb    = 30
      spot            = false
      image_type      = "COS_CONTAINERD"
      disk_type       = "pd-standard"
      logging_variant = "DEFAULT"
      auto_repair     = true
      auto_upgrade    = true
      service_account = "k8s-standard-architecture@${var.project_id}.iam.gserviceaccount.com"
    }
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/servicecontrol"
    ]
  }

  node_pools_labels = {
    all = {}
    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_metadata = {
    all = {}
    default-node-pool = {
      #노드가 종료될 때, kubectl drain 명령어를 사용하여 
      # 파드를 안전하게 제거하고 필요하다면 다른 노드로 재스케줄링 되도록 하는 스크립트를 실행한다.
      shutdown-script                 = "kubectl --kubeconfig=/var/lib/kubelet/kubeconfig drain --force=true --ignore-daemonsets=true --delete-local-data \"$HOSTNAME\""
      node-pool-metadata-custom-value = "default-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    default-node-pool = [
      {
        key    = "default-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      }
    ]
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }

  depends_on = [module.vpc, google_service_account.default]
}
