##############################################################################
# 1) GCP Service Account for Fluent Bit
##############################################################################
resource "google_service_account" "fluent_bit" {
  account_id   = "fluent-bit"
  display_name = "Fluent Bit Service Account"
  project      = var.project_id
}

##############################################################################
# 2) GCS 버킷 (직접 생성하거나, 이미 있다면 data source로 가져오기)
##############################################################################
resource "google_storage_bucket" "fluent_bit_bucket" {
  name          = "fluent-bit-logging-bucket"
  project       = var.project_id
  location      = "US"
  force_destroy = true
  # 기타 버킷 옵션 (버전관리, lifecycle 등)
}

##############################################################################
# 3) 버킷에 대한 IAM 설정 (쓰기 권한)
##############################################################################
resource "google_storage_bucket_iam_member" "fluent_bit_bucket_writer" {
  bucket = google_storage_bucket.fluent_bit_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.fluent_bit.email}"
}

##############################################################################
# 4) Workload Identity 바인딩 (K8s SA -> GCP SA)
##############################################################################
resource "google_service_account_iam_member" "fluent_bit_wi_binding" {
  service_account_id = google_service_account.fluent_bit.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/fluent-bit]"
}
