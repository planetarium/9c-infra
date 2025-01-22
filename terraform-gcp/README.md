# Terraform for EKS cluster

9c-infra에서 terraform을 통해 EKS cluster를 구축하는 방법을 다룹니다.

운영계정은 일반 사용자의 경우 권한문제로 막힐수 있으니 개발 계정에서 진행하는 것을 전제로 합니다.

9c-infra의 terraform은 다음과 같이 구성되어 있습니다.

```yaml
terraform
├── environments
│   ├── 9c-internal
│   │   ├── main.tf
│   │   └── provider.tf
│   └── 9c-sample
│       ├── main.tf
│       └── provider.tf
└── modules
    └── root
        ├── addons.tf
        ├── aws_loadbalancer_controller.tf
        ├── cluster_autoscaler.tf
        ├── eks.tf
        ├── external_dns.tf
        ├── external_secrets.tf
        ├── fluent_bit.tf
        ├── iam.tf
        ├── irsa.tf
        ├── loki.tf
        ├── main.tf
        ├── node_group.tf
        ├── subnet_tags.tf
        ├── variables.tf
        └── vpc.tf
```

environments에서 module을 사용해서 cluster를 생성하도록 되어있습니다.

```yaml
terraform/environments/9c-sample/provider.tf
provider "aws" {
  region  = "us-east-2"
  profile = "dev"
}
```

```yaml
terraform/environments/9c-sample/main.tf
terraform {
  required_providers {
    aws = {
      version = ">= 3"
    }
  }
  required_version = ">= 0.13.0"

  backend "s3" {
    bucket = "terraform-eks-backend"
    key    = "eks/9c-sample"
    region = "us-east-2"
  }
}

module "common" {
  source = "../../modules/root"

  name = "9c-sample"

  create_vpc = false

  # node group
  node_groups = {
    "9c-sample-c5_l_2c" = {
      instance_types    = ["c5.large"]
      availability_zone = "us-east-2c"
      desired_size      = 5
      min_size          = 0
      max_size          = 5
     capacity_type     = "SPOT"
    }
    "9c-sample-r6g_xl_2c" = {
      instance_types    = ["r6g.xlarge"]
      availability_zone = "us-east-2c"
      desired_size      = 5
      min_size          = 0
      max_size          = 10
      capacity_type     = "SPOT"
      ami_type          = "AL2_ARM_64"
    }
  }

  addon_versions = {
    "coredns"            = "v1.10.1-eksbuild.1"
    "kube-proxy"         = "v1.27.1-eksbuild.1"
    "vpc_cni"            = "v1.12.6-eksbuild.2"
    "aws_ebs_csi_driver" = "v1.17.0-eksbuild.1"
  }
}
```

새롭게 cluster를 생성하고자 할 경우 다음의 순서로 진행합니다.

1. `terraform/environments` 에서 9c-sample을 원하는 이름으로 복사합니다.
    
    ```yaml
    $ cp terraform/environments/9c-sample terraform/environments/9c-test
    ```
    
2. `[main.tf](http://main.tf)` 를 다음과 같이 수정합니다.
    
    ```yaml
    terraform/environments/9c-test/main.tf
    terraform {
      required_providers {
        aws = {
          version = ">= 3"
        }
      }
      required_version = ">= 0.13.0"
    
      backend "s3" {
        bucket = "terraform-eks-backend"
        key    = "eks/9c-test"               -> state가 저장될 s3 경로
        region = "us-east-2"
      }
    }
    
    module "common" {
      source = "../../modules/root"
    
      name = "9c-test"                        -> cluster의 이름과 다른 리소스의 prefix
    
      create_vpc = false
    
      # node group
      node_groups = {
        "9c-test-c5_l_2c" = {      -> nodegroup의 이름: cluster 이름이 포함되는 것을 권장
          instance_types    = ["c5.large"]     -> node group의 instance type
          availability_zone = "us-east-2c"
          desired_size      = 5
          min_size          = 0
          max_size          = 5
          capacity_type     = "SPOT"           -> 비용 과다지출을 방지하기 위해 권장합니다.
        }
        "9c-test-r6g_xl_2c" = {
          instance_types    = ["r6g.xlarge"]
          availability_zone = "us-east-2c"
          desired_size      = 5
          min_size          = 0
          max_size          = 1
          capacity_type     = "SPOT"
          ami_type          = "AL2_ARM_64"     -> graviton instance를 사용하는 경우
        }
      }
    
      addon_versions = {
        "coredns"            = "v1.10.1-eksbuild.1"
        "kube-proxy"         = "v1.27.1-eksbuild.1"
        "vpc_cni"            = "v1.12.6-eksbuild.2"
        "aws_ebs_csi_driver" = "v1.17.0-eksbuild.1"
      }
    }
    ```
    
    node group 의 instance type이나 size설정은 필요에 따라 자율적으로 설정합니다.
    
3. `terraform plan` command를 통해 다른 리소스를 수정 혹은 삭제하는 것이 없는지 먼저 확인합니다.(devops 팀에 확인을 요청해주셔도 됩니다.)
4. 문제가 없을 경우 9c-infra에 PR을 올립니다.
5. 승인되면 `terraform apply` 로 적용하고 merge합니다.

(주의) apply 도중 addon 설치에 실패하는 경우가 간혹 있습니다. 생성한 eks버전에 호환되는 addon 버전이 아니기 때문에 발생하는 이슈로, console에서 직접 설치하는 페이지에서 호환되는 버전을 찾아서 넣어주시면 됩니다.
