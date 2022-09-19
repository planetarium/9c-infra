
# Test network from zero(WIP)
이 문서에서는 테스트용 네트워크를 구축하는 절차에 대해 다룹니다.

준비물
 - terraform
 - kubectl
 - awscli
## Setup EKS Cluster 
cluster를 dev계정에 구축하는 것을 기준으로 설명합니다.
### aws credential 설정
AWS dev 계정의 credential을 1password를 참조해서 `~/.aws/credential` 에 입력해줍니다. (1password의 `AWS(dev) Access Key`)
```
# ~/.aws/credentials
...
[planetarium-dev]
aws_access_key_id = <AWS_ACCESS_KEY_ID>
aws_secret_access_key = <AWS_SECRET_ACCESS_KEY>
region = us-east-2
...
```
혹은 aws cli의 `aws configure` 로 입력할 수 있습니다.

### network
본 문서는 cluster를 public network에 구축합니다. 따라서 cluster 및 node group이 통신할 public subnet이 존재해야 합니다.
private subnet을 사용할 경우 NAT gateway가 설정되어 있어야 합니다.
또한 각 subnet에 IP가 충분히 확보되어 있는 상황을 전제합니다.

### terraform
본 문서는 terraform을 이용해 cluster를 구축합니다. 관련 resource들은 전부 `terraform` 폴더에 있습니다.
1. provider.tf에서 profile을 `~/.aws/credentials` 에서 dev계정의 profile을 사용하도록 설정합니다. 
2. 해당 profile을 사용하도록 환경변수를 설정합니다.
     ````
     $ export AWS_PROFILE=planetarium-dev
     ````
3. backend.tf에서 state를 저장할 s3 경로를 지정합니다. 이때 bucket과 key에 해당하는 경로는 미리 존재해야 합니다.
4. variables.tf에서 cluster와 관련된 리소스들의 이름을 정해줍니다.
    ```
	name = "9c-sample"
	instance_types = ["c5.large"]

	desired_size = 10
	max_size = 20
	min_size = 10
     ```
     그 외 vpc나 subnet ID를 수정할 수 있습니다.
     위 변수들은 `variables.tf`에서 어떤 것들이 있는지 확인할 수 있습니다.
5. ```
   $ terraform init
   ```
   terraform state를 지정된 backend에 생성하고 provider를 내려받는 등 initialize작업을 수행합니다.
    ```  
   $ terraform plan
   ```
   plan은 현재 terraform state와 실제 리소스, 사용자의 코드를 비교해서 어떤 부분에 변경이 생길지 보여줍니다. 중요한 리소스가 삭제나 업데이트 되지는 않을지 한번 체크해봅시다.
6. ```
   $ terraform apply
   ```
   terraform plan의 변경사항들을 실제 리소스에 반영합니다. 해당 코드는 다음의 리소스들을 생성합니다.
    - EKS cluster
    - EKS Node Group
    - vpc, subnet tags
    - addons
    - cluster 운영에 필요한 각종 IAM role

## Setup Test Network
testnet 구축에 필요한 k8s manifest를 적용합니다.
cluster를 운영하기 위해 필요한 것들을 아래 bootstrapping과정을 통해 설치합니다.
argoCD를 통한 gitops로 manifest 적용 여부를 판단할 예정이므로, 모든 manifest는 적용하기 전에 github origin에 올라가 있어야 합니다.

### Bootstrap
argoCD, storageClass 등 클러스터 운영에 필요한 것들을 먼저 설치해 주는 과정입니다.
주요 directory 구조는 다음과 같이 되어있습니다.
```
├── README.md
├── application.yaml
├── argocd
│   ├── argocd-cm.yaml
│   ├── argocd-ingress.yaml
│   ├── argocd-rbac-cm.yaml
│   ├── argocd-secrets.yaml
│   ├── bootstrap.yaml
│   └── kustomization.yaml
├── chart
│   ├── Chart.yaml
│   ├── templates
│   │   ├── NOTES.txt
│   │   ├── configmap-probe.yaml
│   │   ├── miner.yaml
│   │   ├── remote-headless.yaml
│   │   ├── secret-private-keys.yaml
│   │   └── seed.yaml
│   └── values.yaml
└── common
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
        │   ├── configmap-probe.yaml
        │   ├── external-dns.yaml
        │   ├── gp2-extensible.yaml
        │   ├── gp3-extensible.yaml
        │   ├── metrics-server.yaml
        │   ├── namespace.yaml
        │   └── service.yaml
        └── values.yaml
```

`argocd/`에 있는 kustomization이 `common/argocd/`에 있는 kustomization을 overlay해서 적용할 예정입니다.
생성한 cluster환경에 맞춰서 `argocd/` 내부 manifest들의 속성들을 변경해줍니다. 주요 변경사항은 다음과 같습니다.
 - `argocd/bootstrap.yaml`의 helm values
	```
	spec:
	project: infra
	source:
	  repoURL: https://github.com/planetarium/k8s-config
	  targetRevision: 9c-sample
	  path: 9c-sample/common/bootstrap
	  helm:
	    values: |
	 >    clusterName: 9c-sample
	 >    accountId: "838612679705"
	```
 - `argocd/kustomization.yaml`의 external-secrets rolename
	```
	    patch: |-
	  - op: add
	    path: /spec/source/helm/values
	    value: |-
	      env:
	        AWS_REGION: ''
	        AWS_DEFAULT_REGION: ''
	        VAULT_ADDR: ''
	      securityContext:
	        fsGroup: 65534
	      serviceAccount:
	        name: 9c-sample-external-secrets
	        annotations:
	 >       eks.amazonaws.com/role-arn: arn:aws:iam::838612679705:role/eks-9c-sample-external-secrets
	```
**external-secrets**는 외부 secret 저장소와 연동하여 원하는 credential을 cluster 내부의 secret resource로 만들고 주기적으로 싱크를 맞춰주는 역할을 담당합니다.
argoCD는 gitops를 따르기 때문에 secret resource를 직접 git에 올리지 않으면서 gitops로 관리하기 위한 최적의 방안으로 생각하여 채택하게 되었습니다.

이번 제안에서는 argoCD가 github private repository(k8s-config)를 조회하기 위한 github token, seed와 miner 노드가 사용할 private key를 AWS에 저장하여 가져오도록 합니다.
secret resource를 gitops로 관리할 의도가 아니라면 external-secrets를 사용하지 않아도 무방합니다. 
```
$ kustomize build argocd/ --reorder none | kubectl apply -f-
```
or
```
$ kubectl apply -k argocd/
```
다음 명령어를 적용하면 kustomization으로 어떤 manifest가 적용되는지 확인 할 수 있습니다.
```
$ kustomize build argocd/
```

**그러나**, 위 커맨드를 입력하면 한번에 모든 resource가 적용되지 못합니다.
argoCD나 external-secrets같은 외부 manifest에서 설치하는 CRD(custom resource definition)들이 먼저 적용되고 난 이후에 그것들을 사용해서 resource를 생성해야 하는데, 한번의 커맨드를 통해 CRD와 그것에 기반한 resource를 같이 적용하는 것은 불가능 합니다.
우선 모든 resource가 성공적으로 적용될 때까지 해당 커맨드를 수행해줘야 합니다.(2~4번 정도)
이러한 문제점을 어떻게 변경할지 고민이 더 필요합니다.
argoCD가 성공적으로 설치되었다면 web UI를 통해 확인할 수 있습니다.  `argocd-server`라는 이름의 service를 통해 load balancer 주소를 얻어서 접속할 수 있습니다.
argocd를 처음 설치하게 되면 admin계정만 존재합니다. password는 argocd namespace에 `argocd-initial-admin-secret`라는 secret을 참조합니다.
로그인에 성공했다면 bootstrap application이 성공적으로 sync되었는지 확인합니다. 실패하고 있다면 github repository와 연동에 실패했을 가능성이 높습니다.
external-secrets가 먼저 설치가 완료되어야 secret을 연동해서 bootstrap이 github repository와 싱크할 수 있게 됩니다. argocd 각 application는 6분주기로 repository와 sync를 맞추게 됩니다. 변경사항이 반영되지 않은 것 같다면 refresh를 해보길 권장합니다.

argoCD는 `Application`이라는 custom resource를 통해 github에서 지정한 경로에 존재하는 manifest나 helm chart들을 cluster와 sync하는 기능을 제공합니다.
`argocd/bootstrap.yaml`에서 bootstrap application을 적용하여 `common/bootstrap/`에 존재하는 helm chart를 렌더링하여 cluster에 적용하도록 합니다.
application resource의 spec.source.targetRevision이 sync를 원하는 github branch와 일치하는지 확인해야 합니다.

### Network
bootstrap 과정이 완료되었다면 `chart/`에 존재하는 network helm chart를 적용할 차례입니다. helm chart는 seed, miner, remote-headless로 구성되어있으며 각각에 필요한 속성들을 `chart/values.yaml`을 통해 주입해줍니다.

**(주의)** 이번 제안에서는 network를 default가 아닌 별도의 namespace에 생성하도록 하였습니다. bootstrap에서 해당 namespace를 생성하니 `common/bootstrap/templates/namespace.yaml`에서 이름을 확인합니다.

다음 커맨드를 통해 어떤 manifest를 적용하게 되는지 미리 확인해볼 수 있습니다.
```
$ helm template 9c-sample chart/ --values chart/values.yaml
```

각 노드들의 value에는 host주소를 여러 개 넣을 수 있고, host주소의 개수만큼 각각 statefulset을 별도로 생성합니다. bootstrap에서 미리 사용할 서비스들을 생성했고, 그 서비스들의 load balancer 주소를 `values.yaml`에 입력해주어야 합니다. 

seed, miner node에서 사용할 private key들을 AWS secrets manager를 참조하여 환경변수로 주입하도록 설정하였습니다. `chart/templates/secret-private-keys.yaml`을 참조하여 `(chart name)/private-keys`라는 이름의 AWS secret을 kubernetes secret으로 올바르게 sync하도록 설정하였습니다.

`application.yaml` 에서 spec.source.targetRevision과 spec.destination.namespace를 sync하려는 github branch와 kubernetes namespace로 수정한 뒤 helm chart와 함께 github에 push합니다.
github와 sync하는 주체는 application resource이기 때문에 `application.yaml`을 apply해줍니다.
```
$ kubectl apply -f application.yaml
```
argoCD web UI에 9c-network라는 이름을 가진 application이 생성되었는지 확인합니다.

현재까지의 설정은 다음과 같은 문제점들이 있습니다. 

 - bootstrap이 완전히 적용될 때까지 여러번 적용해야 합니다.
	 - bootstrap과정을 두 단계로 쪼개는 것으로 문제를 해결할 수는 있습니다.
 - argoCD는 운영용으로만 사용하게 될 가능성이 높지만, network helm chart는 외부 제공용으로도 사용하는 것을 목표로 합니다. 그런데 지금은 이 두 가지가 강하게 coupling되어 있습니다. bootstrap에서 서비스나 storage class, namespace등을 미리 생성하지 않아야 합니다.
	 - storageClass나 namespace는 network chart로 옮겨도 무방할 것 같습니다.
	 - argoCD, 혹은 거기서 설치하고자 하는 external-dns 없이 network helm chart만을 제공하는 경우, k8s service를 생성하면서 argument로 host주소를 넘겨주어야 하기 때문에 chart를 적용한 다음 host를 다시 수정할 필요가 있게 됩니다.

