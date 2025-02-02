variable "project_id" {
  type = string
}

variable "env_name" {
  type    = string
  default = "dev"
}

variable "network" {
  type    = string
  default = "gke-network"
}

variable "subnet_ip" {
  type    = string
  default = "10.10.20.0/24"
}

variable "cluster_name" {
  type    = string
  default = "k8s-standard-architecture"
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "zones" {
  type    = list(string)
  default = ["asia-northeast3-a", "asia-northeast3-b", "asia-northeast3-c"]
}

variable "ip_range_pods_name" {
  type    = string
  default = "subnet-01-pods"
}

variable "ip_range_services_name" {
  type    = string
  default = "subnet-01-services"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "node_min_count" {
  type    = number
  default = 2
}

variable "node_max_count" {
  type    = number
  default = 5
}
