##############################################################################
# 1) Google Service Account
##############################################################################
resource "google_service_account" "lb_controller" {
  account_id   = "custom-lb-controller"
  display_name = "Custom LB Controller Service Account"
  project      = var.project_id
}

##############################################################################
# 2) 부여할 권한: compute.loadBalancerAdmin or networkAdmin 등
##############################################################################
resource "google_project_iam_member" "lb_controller_admin" {
  project = var.project_id
  role    = "roles/compute.loadBalancerAdmin"  # 혹은 roles/compute.networkAdmin
  member  = "serviceAccount:${google_service_account.lb_controller.email}"
}

##############################################################################
# 3) Workload Identity 바인딩
##############################################################################
resource "google_service_account_iam_member" "lb_controller_wi" {
  service_account_id = google_service_account.lb_controller.name
  role               = "roles/iam.workloadIdentityUser"

  # K8s SA: kube-system:aws-load-balancer-controller (AWS 명명 유지)
  member = "serviceAccount:${var.project_id}.svc.id.goog[kube-system/aws-load-balancer-controller]"
}
