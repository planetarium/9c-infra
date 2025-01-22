##############################################################################
# 1) GCP Service Account for External DNS
##############################################################################
resource "google_service_account" "external_dns" {
  account_id   = "external-dns"
  display_name = "External DNS Service Account"
  project      = var.project_id
}

##############################################################################
# 2) Cloud DNS 권한 부여
##############################################################################
# roles/dns.admin : Cloud DNS 관리(Zone, RecordSets) 권한
resource "google_project_iam_member" "external_dns_cloud_dns" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

##############################################################################
# 3) Workload Identity 바인딩
##############################################################################
# AWS IRSA 대신, K8s SA -> GCP SA로 매핑
resource "google_service_account_iam_member" "external_dns_wi" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"

  # namespace:kube-system, serviceaccount:external-dns 와 매핑
  member = "serviceAccount:${var.project_id}.svc.id.goog[kube-system/external-dns]"
}
