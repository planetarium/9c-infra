# auth.tf
# GKE 클러스터에 대한 인증을 구성한다.

module "gke_auth" {
  source               = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  version              = "35.0.1"
  project_id           = var.project_id
  location             = module.gke.location
  cluster_name         = module.gke.name
  use_private_endpoint = true
  depends_on           = [module.gke] 
  # module.gke에 의존한다. 즉 gke에 설정된 클러스터가 생성된 후 인증 정보가 설정된다.
}

# kubeconfig를 로컬 시스템에 저장하여, 쿠버네티스 클러스터에 접근할 수 있도록 한다.

resource "local_file" "kubeconfig" {
  content  = module.gke_auth.kubeconfig_raw
  filename = "kubeconfig-${var.env_name}"
}
