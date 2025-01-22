###############################################################################
# 1) GCP Service Account for Node Pool
###############################################################################
resource "google_service_account" "gke_node_sa" {
  project      = var.project_id
  account_id   = "gke-node-sa"
  display_name = "Service Account for GKE Node Pool"
}

# 필요한 권한을 IAM Binding (AWS "Policy Attachment"와 유사)
resource "google_project_iam_member" "gke_node_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader" # ECR ReadOnly에 대응
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# 예: VPC 권한 (만약 필요하다면)
resource "google_project_iam_member" "gke_node_vpc_access" {
  project = var.project_id
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

###############################################################################
# 2) GKE Node Pool
###############################################################################
resource "google_container_node_pool" "node_pool" {
  name     = "my-node-pool"
  cluster  = google_container_cluster.cluster.name
  location = var.region
  project  = var.project_id

  node_count = 3

  node_config {
    service_account = google_service_account.gke_node_sa.email
    # machine_type = "e2-standard-4"
    # preemptible = true/false
  }
}
