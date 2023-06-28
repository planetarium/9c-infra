# Helm chart for 9c-infra

생성하려는 helm chart를 `charts` directory에서 선택합니다. 그에 대한 `values.yaml` file역시 `{cluster name}/{chart name}/` 에 생성합니다. 준비된 helm chart 목록은 `charts` directory를 참고합니다.

testnet을 구성하려는 경우 `9c-network`를  사용하길 권장합니다.

```yaml
9c-sample
├── 9c-network
│   ├── application.yaml
│   └── values.yaml
├── argocd
    ├── argocd-cm.yaml
    ├── argocd-ingress.yaml
    ├── argocd-rbac-cm.yaml
    ├── argocd-secret-store.yaml
    ├── argocd-secrets.yaml
    ├── bootstrap.yaml
    └── kustomization.yaml
```

value값이 적용된 helm chart가 제대로 설정되었는지 아래 커맨드를 통해 확인 가능합니다.

```bash
$ helm template 9c-sample charts/9c-network --values 9c-sample/9c-network/values.yaml
```

### values.yaml

`charts` directory에 있는 chart들을 보면, `values.yaml`에 default value들을 가지고 있는 것을 확인할 수 있습니다. `{cluster name}/{chart name}/values.yaml` 에는 위 default value에서 변경이 필요한 값들만 적으면 나머지는 default value가 자동으로 들어가게 되어 있습니다.

예시로 `9c-sample/9c-network/values.yaml` 에 명시된 value들은 `charts/9c-network/values.yaml` 에서 변경이 필요한 값들만을 반영하여 명시했기 때문에 훨씬 작습니다.

[https://github.com/planetarium/9c-infra/blob/main/9c-sample/9c-network/values.yaml](https://github.com/planetarium/9c-infra/blob/main/9c-sample/9c-network/values.yaml)

### secret 관리

argocd를 사용하는 경우 github에 반영된 `values.yaml` 로 sync되는데, value에 private key등 secret들이 포함되어 있습니다. secret value들을 github에 올릴수 없는 관계로, 위 `github-token` 과 같은 방식으로 external-secrets를 통해 관리하도록 합니다. `values.yaml` 의 `useExternalSecrets` 를 true로 설정하게 되면 private key, slack token 등을 secretsmanager에서 가져오도록 합니다.

dev계정의 `9c-sample/private-keys`, `9c-sample/slack` 을 참조하여 이름을 맞춰 생성합니다.

argocd를 사용하지 않는다면 다음 커맨드로 클러스터에 적용합니다.

```bash
$ helm template {network name} charts/9c-network --values {cluster name}/{chart name}/values.yaml
```
