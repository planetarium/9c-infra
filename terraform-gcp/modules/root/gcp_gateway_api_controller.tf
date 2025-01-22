##############################################################################
# 1) GCP Service Account
##############################################################################
resource "google_service_account" "gateway_api_controller" {
  account_id   = "gateway-api-controller"
  display_name = "Gateway API Controller Service Account"
  project      = var.project_id
}

##############################################################################
# 2) 필요한 IAM Roles (예시)
##############################################################################
# 아래 roles는 예시이며, 실제로 어떤 API를 쓰느냐에 따라 달라집니다.
# - Traffic Director admin => roles/trafficdirector.admin
# - Logging 관리자 => roles/logging.admin
# - Compute Network admin => roles/compute.networkAdmin
# 등등
resource "google_project_iam_member" "gateway_api_controller_admin" {
  project = var.project_id
  role    = "roles/trafficdirector.admin"
  member  = "serviceAccount:${google_service_account.gateway_api_controller.email}"
}

resource "google_project_iam_member" "gateway_api_controller_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gateway_api_controller.email}"
}

# 필요 시 Storage(예: "s3:PutBucketPolicy"에 해당) -> GCS => roles/storage.admin?
# resource "google_project_iam_member" "gateway_api_controller_storage" {
#   project = var.project_id
#   role    = "roles/storage.admin"
#   member  = "serviceAccount:${google_service_account.gateway_api_controller.email}"
# }

##############################################################################
# 3) Workload Identity 바인딩
##############################################################################
resource "google_service_account_iam_member" "gateway_api_controller_wi" {
  service_account_id = google_service_account.gateway_api_controller.name
  role               = "roles/iam.workloadIdentityUser"

  # namespace: aws-application-networking-system
  # serviceaccount: gateway-api-controller
  member = "serviceAccount:${var.project_id}.svc.id.goog[aws-application-networking-system/gateway-api-controller]"
}
