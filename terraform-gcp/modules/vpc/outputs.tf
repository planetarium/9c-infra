output "network_name" {
  description = "VPC name"
  value       = module.vpc.network_name
}

output "subnets_names" {
  description = "List of subnets"
  value       = module.vpc.subnets_names
}
