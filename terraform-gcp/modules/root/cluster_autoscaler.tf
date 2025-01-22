##############################################################################
# 1) GCP Service Account for Cluster Autoscaler
##############################################################################
resource "google_service_account" "cluster_autoscaler" {
  account_id   = "cluster-autoscaler"
  display_name = "Cluster Autoscaler Service Account"
  project      = var.project_id
}

##############################################################################
# 2) IAM Role Binding
#    - CA가 GKE Node Pool을 조작하려면, container.admin 혹은 container.clusterAdmin 등이 필요
##############################################################################
resource "google_project_iam_member" "cluster_autoscaler_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.cluster_autoscaler.email}"
}

# 추가로, GKE 노드 제어에 compute.instanceAdmin 등이 필요한 경우가 있으나,
# 대부분 container.admin 권한에 포함돼 있습니다.

##############################################################################
# 3) Workload Identity 바인딩
#    - K8s SA (kube-system/aws-cluster-autoscaler) -> GCP SA
##############################################################################
resource "google_service_account_iam_member" "cluster_autoscaler_wi" {
  service_account_id = google_service_account.cluster_autoscaler.name
  role               = "roles/iam.workloadIdentityUser"
  
  member = "serviceAccount:${var.project_id}.svc.id.goog[kube-system/aws-cluster-autoscaler]"
}
