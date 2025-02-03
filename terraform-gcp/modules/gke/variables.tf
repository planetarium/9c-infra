variable "project_id" {
  type = string
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

variable "network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "ip_range_pods_name" {
  type = string
}

variable "ip_range_services_name" {
  type = string
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
