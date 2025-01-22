resource "google_container_node_pool" "node_groups" {
  for_each = var.node_groups

  # Node Pool 이름
  name       = each.key
  # GKE 클러스터 정보
  cluster    = google_container_cluster.cluster.name
  project    = var.project_id         # 예: variables로 관리
  location   = var.region             # 리전 or 클러스터와 동일한 리전/존

  # GKE는 기본적으로 node_count / initial_node_count가 필요 (desired_size)
  node_count = each.value.desired_size

  # 자동확장 설정
  autoscaling {
    min_node_count = each.value.min_size
    max_node_count = each.value.max_size
  }

  # 노드 설정
  node_config {
    # AWS의 instance_types(배열) 중 첫 번째를 사용 (또는 원하는 로직)
    machine_type = length(each.value.instance_types) > 0 ? each.value.instance_types[0] : "e2-standard-2"

    # capacity_type => SPOT 시 preemptible = true
    preemptible = (
      try(each.value.capacity_type, "ON_DEMAND") == "SPOT" ? true : false
    )

    # ami_type(AWS AL2_x86_64 등)은 GKE에서 사용 안 함.
    # 대신 image_type 설정 가능
    # image_type = "COS_CONTAINERD"

    # GCP에서 노드에 taint를 적용하려면 아래와 같은 구조
    dynamic "taints" {
      for_each = try(each.value.taints, [])
      content {
        key    = taints.value.key
        value  = taints.value.value
        effect = taints.value.effect # NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE
      }
    }
  }

  # GCP에선 서브넷 지정 시:
  # (AWS에서 subnet_ids => GCP에서 subnetwork)
  # - 만약 var.create_vpc가 true라면: google_compute_subnetwork.public[ each.value["availability_zone"] ].self_link
  # - 아니면 var.public_subnet_ids[0] 처럼 하나를 선택
  # 주의: GCP에서는 zone/region 개념과 subnet key 매핑이 AWS와 달라 조정 필요

  dynamic "network_config" {
    for_each = var.create_vpc ? [each.value] : []
    content {
      subnetwork = google_compute_subnetwork.public[each.value.availability_zone].self_link
      # alias_ip_range = ...
    }
  }

  # depends_on 예시
  depends_on = [
    google_container_cluster.cluster,
    # 서브넷 리소스를 Terraform에서 관리 중이라면 해당 리소스
    google_compute_subnetwork.public,
  ]
}
