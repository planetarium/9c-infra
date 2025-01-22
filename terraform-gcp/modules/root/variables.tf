##############################################################################
# variables.tf for GCP
##############################################################################

variable "name" {
  description = "General name for cluster related resources."
  type        = string
  default     = "common-9c-infra-name"
}

################################################################################
# VPC(Network) 관련
################################################################################

variable "create_vpc" {
  description = "Boolean to create new GCP VPC (Network). If false, use existing VPC."
  type        = bool
  default     = false
}

variable "vpc_name" {
  description = "New VPC (Network) name in GCP"
  type        = string
  default     = "common-terraform-vpc-name"
}

variable "vpc_cidr_block" {
  description = "CIDR block for new VPC in GCP (custom mode). E.g., 10.0.0.0/16"
  type        = string
  default     = "10.0.0.0/16"
}

# 기존 VPC(= GCP Network) 사용 시: self_link 또는 network 이름을 넣어 사용할 수 있음
variable "vpc_id" {
  description = <<EOT
In GCP, this could be the self_link or name of an existing Network.
For example:
- "projects/<PROJECT_ID>/global/networks/<NETWORK_NAME>" (self_link) 
- or just "<NETWORK_NAME>" if your provider config is set to the correct project
EOT
  type    = string
  default = "projects/my-gcp-project/global/networks/existing-network"
}

################################################################################
# Subnet(서브넷) 관련
################################################################################

# AWS에서 public_subnet_ids 같은 것을 GCP에선 subnetwork self_link, region 등이 필요
variable "public_subnet_ids" {
  description = <<EOT
In GCP, use subnetwork self_links or names for existing public subnetworks, e.g.:
"projects/<PROJECT_ID>/regions/<REGION>/subnetworks/<SUBNET_NAME>"
EOT
  type    = list(string)
  default = [
    "projects/my-gcp-project/regions/us-east1/subnetworks/public-subnet-1",
    "projects/my-gcp-project/regions/us-east1/subnetworks/public-subnet-2"
  ]
}

# 새로 VPC를 만들 때 생성할 "퍼블릭" 서브넷 정보 (region -> CIDR)
# GCP는 zone 단위가 아니라 region 단위로 subnet 생성
variable "public_subnets" {
  description = "map {region = cidr} for new public subnets (GCP custom mode)"
  type        = map(string)
  default = {
    "us-east1" = "10.0.0.0/20"
    # "us-east1" = "10.0.16.0/20"  // 여러 개 생성 시 key가 같으면 안 되므로 주의
  }
}

# 새로 VPC를 만들 때 생성할 "프라이빗" 서브넷 정보
variable "private_subnets" {
  description = "map {region = cidr} for new private subnets (GCP custom mode)"
  type        = map(string)
  default = {
    "us-east1" = "10.0.128.0/20"
  }
}

################################################################################
# GKE Node Pool(= EKS node group 비슷한 구조)
################################################################################

# 기존 EKS node_groups 구조를 GKE node_pools 형태로 비슷하게
# machine_types, location(us-east1, us-east1-b 등), desired_size, etc.
variable "node_groups" {
  description = <<EOT
Map of Node Group config -> will translate to GKE node pools.
Keys:
  - instance_types     -> list of GCP machine types (e.g. ["e2-standard-2"])
  - availability_zone  -> in GCP, might be region or zone (e.g. "us-east1-b")
  - desired_size
  - min_size
  - max_size
  - taints -> list of taints if needed (GKE supports taints)
EOT
  type = map(object({
    instance_types     = list(string)
    availability_zone  = string
    desired_size       = number
    min_size           = number
    max_size           = number
    taints             = list(string)
  }))

  default = {
    "9c-sample" = {
      instance_types    = ["e2-standard-2"]  # GCP machine type
      availability_zone = "us-east1-b"       # GCP zone
      desired_size      = 10
      min_size          = 10
      max_size          = 20
      taints            = []
    }
  }
}

# 아래 변수들은 EKS에서 노드 그룹 공통 설정용으로 쓰던 것
# GKE에서도 공통 node pool 파라미터로 쓸 수 있음

variable "instance_types" {
  description = "Default GCP machine types if not specified in node_groups"
  type        = list(string)
  default     = ["e2-standard-2"]
}

variable "desired_size" {
  description = "Node group desired size"
  type        = number
  default     = 10
}

variable "max_size" {
  description = "Node group max size"
  type        = number
  default     = 20
}

variable "min_size" {
  description = "Node group min size"
  type        = number
  default     = 10
}

################################################################################
# Addon versions (EKS 개념이지만, GKE에서는 별도로 관리 X)
################################################################################
variable "addon_versions" {
  description = <<EOT
List of addon versions. For EKS it was coredns, kube-proxy, vpc_cni, aws_ebs_csi_driver, etc.
GKE에는 직접 설정하지 않아도 자동 관리되므로, 여기서는 참고용 (N/A)으로 남겨둠.
EOT
  type = map(string)
  default = {
    "coredns"            = "N/A - GKE managed"
    "kube-proxy"         = "N/A - GKE managed"
    "vpc_cni"            = "N/A - GKE managed"
    "aws_ebs_csi_driver" = "N/A - uses GCE PD CSI"
  }
}

################################################################################
# Loki Bucket (AWS -> S3) => GCP -> GCS
################################################################################

variable "loki_bucket" {
  description = "Loki's GCS bucket name (equivalent to S3 in AWS)"
  type        = string
  default     = "loki-dev.planetariumhq.com"
}

