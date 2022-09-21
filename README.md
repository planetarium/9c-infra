# Guide for Setting Up Test Clusters
이 문서에서는 테스트용 네트워크를 [AWS dev 계정](https://start.1password.com/open/i?a=SGC2PENG75GZVAYBIM7ZDAK6XE&h=planetarium.1password.com&i=bbi6tmt4hyynp6hvace6ytmwqy&v=7zjxhskpdxvoznqnvhdi3iam4i)에 구축하는 것을 기준으로 설명합니다.

## A. 준비
------

### 1. 설치 필요
 - [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform)
 - [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
 - [awscli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
 - [helm](https://helm.sh/docs/intro/install/)

### 2. AWS credential 설정
AWS dev 계정의 credential을 [1password](https://start.1password.com/open/i?a=SGC2PENG75GZVAYBIM7ZDAK6XE&v=7zjxhskpdxvoznqnvhdi[…]4i&i=tnnwtjxlngcxzo7soiimfx5x6q&h=planetarium.1password.com)를 참조해서 `~/.aws/credential` 에 입력해줍니다. (1password의 `AWS(dev) Access Key`)
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

## B. 테스트 클러스터 생성 with Terraform
------
본 문서는 terraform을 이용해 cluster를 구축합니다. 관련 resource들은 전부 `terraform` 폴더에 있습니다.
### 중요 사항
- 아래 예제는 `9c-sample`이라는 클러스터를 구축하는 단계로 정리 돼있습니다.
- **다른 명칭의 클러스터를 구축하고 싶다면 `9c-sample` 폴더를 원하는 클러스터 이름으로 변경하고 변경된 폴더 내의 `9c-sample` 명칭을 변경한 이름으로 모두 바꿔주시면 됩니다 (아래 4번 참조).**
### 구축 순서
1. `terraform/provider.tf`에서 profile을 `~/.aws/credentials` 에서 dev계정의 profile을 사용하도록 설정합니다. 
2. 해당 profile을 사용하도록 환경변수를 설정합니다.
     ````
     $ export AWS_PROFILE=planetarium-dev
     ````
3. `terraform/backend.tf`에서 state를 저장할 s3 경로를 지정합니다. 이때 bucket과 key에 해당하는 경로는 미리 존재해야 합니다.
4. 아래 나열된 파일 내의 `9c-sample` 명칭들을 원하는 클러스터 이름으로 변경해줍니다 (예: `9c-test`)
  - `application.yaml`
  - `argocd/bootstrap.yaml`
  - `argocd/kustomization.yaml`
  - `chart/Chart.yaml`
  - `common/bootstrap/values.yaml`
  - `common/bootstrap/templates/argocd-app.yaml`
  - `common/bootstrap/templates/namespace.yaml`
  - `common/bootstrap/templates/service.yaml`
  - `terraform/backend.tf`
  - `terraform/terraform.tfvars`
  - `terraform/variables.tf`
  - `terraform/.terraform/terraform.tfstate`
5. `terraform/variables.tf`에서 cluster와 관련된 리소스들의 이름을 정해줍니다.
    ```
    name = "9c-sample"
    instance_types = ["c5.large"]

    desired_size = 10
    max_size = 20
    min_size = 10
     ```
     그 외 vpc나 subnet ID를 수정할 수 있습니다.
     위 변수들은 `terraform/variables.tf`에서 어떤 것들이 있는지 확인할 수 있습니다.
6. `terraform` directory 경로에서 아래 커맨드를 실행해줍니다.
   ```
   $ terraform init
   ```
   terraform state를 지정된 backend에 생성하고 provider를 내려받는 등 initialize작업을 수행합니다.
    ```  
   $ terraform plan
   ```
   plan은 현재 terraform state와 실제 리소스, 사용자의 코드를 비교해서 어떤 부분에 변경이 생길지 보여줍니다. 중요한 리소스가 삭제나 업데이트 되지는 않을지 한번 체크해봅시다.
7. ```
   $ terraform apply
   ```
   terraform plan의 변경사항들을 실제 리소스에 반영합니다. 해당 코드는 다음의 리소스들을 생성합니다.
    - EKS cluster
    - EKS Node Group
    - vpc, subnet tags
    - addons
    - cluster 운영에 필요한 각종 IAM role
8. AWS dev 계정 `EKS`와 `S3`에 들어가서 리소스가 잘 생성됐는지 확인해봅니다.

## C. 네트워크 및 노드 띄우기 with Helm
------
1. `chart/values.yaml`에서 `useExternalSecret` 값을 `false`로 바꿔주고 `seed` 와 `miner`의 `privateKeys` 값을 넣어줍니다.
- ex) `privateKeys: ["XXXXXX"]`

2. `9c-sample` directory 경로에서 아래 커맨드를 실행해줍니다.
  ```
  helm template 9c-sample chart/ --values chart/values.yaml | kubectl apply -f-
  ```
3. 클러스터에 접속해서 노드 상태를 확인해봅니다.
  ```
  kubectl get pod -n 9c-sample --watch
  ```
  또는 [Lens](https://k8slens.dev/)로 확인 가능합니다.
