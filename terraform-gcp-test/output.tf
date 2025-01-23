# output.tf
# 리소스에서 생성된 데이터를 출력하는데 사용된다. output을 사용하면 원하는 정보를 개발환경에서도 바로 확인할 수 있다.

output "cluster_id" {
  description = "cluster id"
  value       = module.gke.cluster_id
}

output "cluster_name" {
  description = "cluster name"
  value       = module.gke.name
}

output "ca_certificate" {
  sensitive   = true
  description = "Cluster ca certificate (base64 encoded)"
  value       = module.gke.ca_certificate
}

output "cluster_type" {
  description = "cluster type (regional / zonal)"
  value       = module.gke.type
}

output "cluster_location" {
  description = "Cluster location (region if regional cluster, zone if zonal cluster)"
  value       = module.gke.location
}

output "horizontal_pod_autoscaling_enabled" {
  description = "Whether horizontal pod autoscaling enabled"
  value       = module.gke.horizontal_pod_autoscaling_enabled
}

output "http_load_balancing_enabled" {
  description = "Whether http load balancing enabled"
  value       = module.gke.http_load_balancing_enabled
}

output "master_authorized_networks_config" {
  description = "Networks from which access to master is permitted"
  value       = module.gke.master_authorized_networks_config
}

output "cluster_region" {
  description = "Cluster region"
  value       = module.gke.region
}

output "cluster_zones" {
  description = "List of zones in which the cluster resides"
  value       = module.gke.zones
}

output "cluster_endpoint" {
  sensitive   = true
  description = "Cluster endpoint"
  value       = module.gke.endpoint
}

output "min_master_version" {
  description = "Minimum master kubernetes version"
  value       = module.gke.min_master_version
}

output "logging_service" {
  description = "Logging service used"
  value       = module.gke.logging_service
}

output "monitoring_service" {
  description = "Monitoring service used"
  value       = module.gke.monitoring_service
}

output "master_version" {
  description = "Current master kubernetes version"
  value       = module.gke.master_version
}

output "network_policy_enabled" {
  description = "Whether network policy enabled"
  value       = module.gke.network_policy_enabled
}

output "node_pools_names" {
  description = "List of node pools names"
  value       = module.gke.node_pools_names
}

output "node_pools_versions" {
  description = "Node pool versions by node pool name"
  value       = module.gke.node_pools_versions
}

output "service_account" {
  description = "The service account to default running nodes as if not overridden in node_pools."
  value       = module.gke.service_account
}
