
# 9c-infra 사용가이드

- [9c-infra](https://github.com/planetarium/9c-infra)의 다양한 용도 및 사용방법을 다룹니다.
- 현재(2023/06/26)의 9c-main, 9c-internal의 상태는 본 가이드에서 제시하는 구조를 따르지 않고 있습니다.

### 역할

 9c-infra는 nine chronicles 노드에 기반한 infra를 코드로 관리하기 위한 목적으로 탄생하였습니다. 여기에서 infra라 함은 EKS cluster를 운영하기 위해 필요한 AWS resource들과, cluster 내부에 구축되는 kubernetes resource들로 이루어집니다. 또한 관리라 함은, 그러한 리소스들에 대한 여러 가지 설정 정보들을 코드로 관리함으로서 얻는 재활용성, 멱등성 등의 장점을 취하고, PR-merge 구조를 통해 변경되는 설정을 안전하게 적용하고 그 이력을 쉽게 남기려는 측면을 이야기 합니다.

 현재 9c-infra에서는 AWS resource는 terraform으로, k8s resource는 helm chart를 통해 관리하고자 합니다. 또한 9c-infra에 올라가는 helm chart의 상태가 EKS cluster에 잘 반영되도록 argoCD를 통해 gitops를 적용합니다.

 장기적으로는 여기에 위치한 일부 helm chart는 public repository에까지 배포 및 관리되어 외부 사용자로 하여금 쉽게 설치 및 운영하는 것을 목표로 합니다.

### 구성

9c-infra가 앞서 언급한 resource를 관리하는 도구들을 사용하는 방식을 살펴봅니다.

root directory를 보면 다음과 같이 구성되어 있습니다.

```
9c-infra
├── 9c-internal
├── 9c-main
├── 9c-sample
├── GUIDE.md
├── LICENSE
├── README.md
├── charts
├── common
├── scripts
└── terraform
```

- 9c-*
    - 각 클러스터별 설정을 가지고 있습니다.
    - terraform
    - `terraform` directory에 [module](https://developer.hashicorp.com/terraform/language/modules)과 environments로 나누어서 관리합니다.
    
    ```
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
    
    - `terraform/environments/9c-sample` 에서 `terraform apply` 로 적용합니다.
    - charts
    - `charts` directory에 용도별로 관리합니다.
    
    ```
    charts
    ├── 9c-network
    │   ├── Chart.yaml
    │   ├── templates
    │   │   ├── configmap-download-snapshot.yaml
    │   │   ├── ...
    │   │   └── validator.yaml
    │   └── values.yaml
    ├── all-in-one
    │   ├── Chart.yaml
    │   ├── templates
    │   │   ├── bridge.yaml
    │   │   ├── configmap-data-provider.yaml
    │   │   ├── ...
    │   │   ├── validator.yaml
    │   │   └── worldboss.yaml
    │   └── values.yaml
    ├── ...
    ├── validator
    │   ├── Chart.yaml
    │   ├── templates
    │   │   ├── configmap-download-snapshot.yaml
    │   │   ├── ...
    │   │   └── validator.yaml
    │   └── values.yaml
    └── world-boss
        ├── Chart.yaml
        ├── templates
        │   ├── secret-store.yaml
        │   ├── ...
        │   └── worldboss.yaml
        └── values.yaml
    ```
    
    - `all-in-one`: 현재 9c-main과 동일한 구성으로 모든 컴포넌트를 포함합니다.
    - `9c-network`: testnet 목적으로 존재하는 chart로 다음의 요소들만 포함합니다.
        - validator
        - remote-headless
        - seed
    - 위 두 chart를 제외한 나머지는 namespace를 직접 생성해주지 않기 때문에 value로 주입해야 합니다.
    - argoCD
    - argoCD에 관련된 설정은 클러스터별로 공통으로 가지고 있는 설정은 `common` directory에 모아두고, 개별적으로 가지고 있는 설정들은 각 클러스터의 `argocd` 디렉토리에서 보관합니다.
    
    ```
    common
    ├── argocd
    │   ├── deployment.yaml
    │   ├── kubernetes-external-secrets.yaml
    │   ├── kustomization.yaml
    │   └── namespace.yaml
    └── bootstrap
        ├── Chart.yaml
        ├── templates
        │   ├── argocd-app.yaml
        │   ├── aws-cluster-autoscaler.yaml
        │   ├── aws-load-balancer-controller.yaml
        │   ├── external-dns.yaml
        │   ├── fluent-bit
        │   │   ├── configmap-fluent-bit.yaml
        │   │   └── fluent-bit.yaml
        │   ├── gp3-extensible.yaml
        │   ├── grafana.yaml
        │   ├── loki.yaml
        │   ├── memcached.yaml
        │   ├── metrics-server.yaml
        │   ├── namespace-monitoring.yaml
        │   └── prometheus.yaml
        └── values.yaml
    ```
    
    ```
    9c-main/argocd
    ├── argocd-cm.yaml
    ├── argocd-ingress.yaml
    ├── argocd-node-selectors.yaml
    ├── argocd-rbac-cm.yaml
    ├── argocd-secret-store.yaml
    ├── argocd-secrets.yaml
    ├── bootstrap.yaml
    └── kustomization.yaml
    ```
    
    - `9c-main/argocd` 에서 kustomize를 통해 common에 있는 설정까지 한꺼번에 반영합니다.
    
    ```yaml
    $ kustomize build 9c-main/argocd/ | kubectl apply -f-
    ```
    
    - 이 과정에서 별도로 정의한 `bootstrap` 이라는 helm chart를 적용하여 클러스터 운영 전반에 필요한 도구들을 설치합니다.
    - example
    
    ```
    9c-sample
    ├── 9c-network
    │   ├── application.yaml
    │   └── values.yaml
    ├── argocd
    │   ├── argocd-cm.yaml
    │   ├── argocd-ingress.yaml
    │   ├── argocd-rbac-cm.yaml
    │   ├── argocd-secret-store.yaml
    │   ├── argocd-secrets.yaml
    │   ├── bootstrap.yaml
    │   └── kustomization.yaml
    ├── data-provider
    │   ├── application.yaml
    │   └── values.yaml
    └── explorer
        ├── application.yaml
        └── values.yaml
    ```
    
    - argocd에서 bootstrap, kustomization등 필요한 설정 준비
    - 그 외 각 application별로 `application.yaml` , helm chart의 `values.yaml` 준비
    - argocd에서는 `Application` 이라는 리소스를 통해 github repository의 특정 경로에 존재하는 manifest를 cluster와 sync하도록 설정합니다. `application.yaml` 은 그러한 `Application` 리소스를 정의하는 manifest입니다.
    - 단순한 manifest도 sync할 수 있지만 일반적으로 helm chart를 이용하는 편이 더 많은 이점을 제공합니다.
    - argocd의 구성 및 사용방법은 추후 더 자세히 다룰 예정입니다.
