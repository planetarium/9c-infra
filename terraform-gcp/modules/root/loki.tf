##############################################################################
# 1) GCP Service Account
##############################################################################
resource "google_service_account" "loki" {
  account_id   = "loki"
  display_name = "Service Account for Loki"
  project      = var.project_id
}

##############################################################################
# 2) GCS Bucket (혹은 이미 존재하는 버킷)
##############################################################################
resource "google_storage_bucket" "loki_bucket" {
  name     = var.loki_bucket
  project  = var.project_id
  location = "US"
  # versioning, lifecycle 등 필요시 추가
}

##############################################################################
# 3) Grant Service Account -> GCS Bucket Access
##############################################################################
resource "google_storage_bucket_iam_member" "loki_bucket_access" {
  bucket = google_storage_bucket.loki_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.loki.email}"
}

##############################################################################
# 4) Workload Identity: K8s Service Account -> GCP Service Account
##############################################################################
resource "google_service_account_iam_member" "loki_wi_binding" {
  service_account_id = google_service_account.loki.name
  role               = "roles/iam.workloadIdentityUser"

  # monitoring:loki => K8s namespace: "monitoring", SA: "loki"
  # GKE project = var.project_id
  # cluster must have Workload Identity enabled
  member = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/loki]"
}

