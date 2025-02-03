module "gke_auth" {
  source               = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  version              = "35.0.1"
  project_id           = var.project_id
  location             = var.region
  cluster_name         = var.cluster_name
  use_private_endpoint = true
  depends_on           = [module.cluster]
}

resource "local_file" "kubeconfig" {
  content  = module.gke_auth.kubeconfig_raw
  filename = "kubeconfig-${var.cluster_name}"
}
