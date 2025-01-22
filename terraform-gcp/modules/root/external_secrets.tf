##############################################################################
# 1) GCP Service Account for External Secrets
##############################################################################
resource "google_service_account" "external_secrets" {
  account_id   = "external-secrets"
  display_name = "External Secrets Service Account"
  project      = var.project_id
}

##############################################################################
# 2) Secret Manager: 예시로 특정 Secret을 이미 만들었다고 가정
#    (직접 Terraform으로 생성하거나, data source로 가져올 수도 있음)
##############################################################################
resource "google_secret_manager_secret" "example_secret" {
  secret_id  = "my-example-secret"
  project    = var.project_id
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "example_secret_version" {
  secret      = google_secret_manager_secret.example_secret.id
  secret_data = "my super secret"
}

##############################################################################
# 3) Grant 'secretAccessor' role to External Secrets SA
##############################################################################
# Broad project-level binding (can read all secrets in the project),
# or per-secret binding using `google_secret_manager_secret_iam_member`.
# 여기서는 'project' 전체 시크릿 액세스 권한 부여 예시
resource "google_project_iam_member" "external_secrets_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

##############################################################################
# 4) Workload Identity: K8s SA -> GCP SA Binding
##############################################################################
resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  # AWS 예제: "system:serviceaccount:kube-system:${var.name}-external-secrets"
  # GCP에서는 "[namespace]/[serviceaccount]" 형태로 mapping
  member = "serviceAccount:${var.project_id}.svc.id.goog[kube-system/${var.name}-external-secrets]"
}
