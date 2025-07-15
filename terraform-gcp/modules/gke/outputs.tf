output "cluster_endpoint" {
  description = "Cluster endpoint"
  value       = module.cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = module.cluster.ca_certificate
  sensitive   = true
}

output "cluster_name" {
  description = "Cluster name"
  value       = module.cluster.name
}
