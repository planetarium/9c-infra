project_id               = "nine-chronicles-449809"
env_name                 = "dev"
network                  = "gke-network"
subnet_ip                = "10.10.20.0/24"
cluster_name             = "main"
region                   = "us-east5"
zones                    = ["us-east5-a", "us-east5-b", "us-east5-c"]
ip_range_pods_name       = "subnet-01-pods"
ip_range_services_name   = "subnet-01-services"
node_machine_type        = "e2-standard-8"
node_min_count           = 2
node_max_count           = 5
