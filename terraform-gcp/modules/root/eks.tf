resource "google_container_cluster" "cluster" {
  name               = var.name
  project            = var.project_id
  location           = var.region
  # (us-east1, asia-northeast3 등)

  # VPC / Subnetwork 설정
  # AWS "vpc_config.subnet_ids" → GCP "network" + "subnetwork"
  # var.create_vpc ? (직접 만든 subnetwork.self_link) : 기존 subnet self_link
  network    = var.create_vpc
    ? google_compute_network.my_vpc.self_link
    : var.existing_network_self_link       # 예: "projects/<PROJECT_ID>/global/networks/<NET_NAME>"

  subnetwork = var.create_vpc
    ? google_compute_subnetwork.public_subnet.self_link
    : var.existing_subnetwork_self_link    # 예: "projects/<PROJECT_ID>/regions/<REGION>/subnetworks/<SUBNET_NAME>"

  # GKE에서는 IP 할당 정책이 중요
  ip_allocation_policy {
    use_ip_aliases = true
  }

  # GKE releases
  release_channel {
    channel = "STABLE"
  }

  # 필요 시 Private Cluster 등 설정
  # private_cluster_config {
  #   enable_private_nodes    = true
  #   enable_private_endpoint = false
  #   master_ipv4_cidr_block  = "172.16.0.0/28"
  # }

  depends_on = [
    google_compute_subnetwork.public_subnet
  ]
}
