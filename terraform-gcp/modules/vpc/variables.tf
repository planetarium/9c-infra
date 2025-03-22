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

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "ip_range_pods_name" {
  type    = string
  default = "subnet-01-pods"
}

variable "ip_range_services_name" {
  type    = string
  default = "subnet-01-services"
}
