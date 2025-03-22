# Create a service account for the nodes
resource "google_service_account" "default" {
  account_id   = "k8s-standard-architecture"
  project      = var.project_id
  display_name = "K8s Standard Architecture Service Account"
  description  = "Service account for K8s standard architecture"
}

# Create a private GKE cluster
module "cluster" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "35.0.1"

  project_id                 = var.project_id
  name                       = var.cluster_name
  region                     = var.region
  zones                      = var.zones
  network                    = var.network_name
  subnetwork                 = var.subnet_name
  ip_range_pods              = var.ip_range_pods_name
  ip_range_services          = var.ip_range_services_name
  http_load_balancing        = true
  network_policy             = true
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false

  enable_private_endpoint = false
  enable_private_nodes    = true
  master_ipv4_cidr_block  = "10.0.0.0/28"

  deletion_protection = false

  node_pools = [
    {
      name            = "default-node-pool"
      machine_type    = var.node_machine_type
      node_locations  = join(",", var.zones)
      min_count       = var.node_min_count
      max_count       = var.node_max_count
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
      # When the node shuts down, automatically drain Pods
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

  depends_on = [google_service_account.default]
}
