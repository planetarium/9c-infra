set -e

find . -type d -name templates -not -path "./charts/all-in-one/*" -print | while read -r dir
do
    chart_dir=$(dirname "$dir")
    echo "Validating $chart_dir..."
    helm lint "$chart_dir"
    helm template "$chart_dir" | ./kubeconform -strict -summary -skip "TCPRoute" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done

# Check multiplanetary networks manually
CLUSTERS=("9c-main" "9c-internal")
NETWORKS=("odin" "heimdall")
for cluster in "${CLUSTERS[@]}"; do
    for network in "${NETWORKS[@]}"; do
        helm template --values "$cluster/network/$network.yaml" \
            --values "$cluster/network/general.yaml" \
            "charts/all-in-one" | ./kubeconform -strict -summary -skip "TCPRoute" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
    done
done

# charts/portal 은 오버레이로도 렌더한다.
#   위 루프는 **기본 values 로만** 돌기 때문에, 기본이 enabled: false 인 기능
#   (walletBalanceReport, withdrawalBacklogAlert 등)의 렌더 경로가 CI 에서 한 번도
#   실행되지 않는다. 그런 템플릿의 오류는 ArgoCD sync 시점에야 드러나고, 포탈 앱
#   sync 가 막히면 장애 중 이미지 롤백까지 같이 막힌다.
for cluster in "${CLUSTERS[@]}"; do
    echo "Validating charts/portal with $cluster overlay..."
    helm template --values "$cluster/portal/values.yaml" \
        "charts/portal" | ./kubeconform -strict -summary -skip "TCPRoute" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done

# 기간 유지 워커는 기본값에서 비활성이므로 실제 RB 오버레이도 검증한다.
RB_OVERLAYS=(
    "9c-main/ragnarok-breaker-prod-web2/values.yaml"
    "9c-main/ragnarok-breaker-prod-web3/values.yaml"
    "9c-main/ragnarok-breaker-prod/values.yaml"
    "9c-internal/ragnarok-breaker-staging-web2/values.yaml"
    "9c-internal/ragnarok-breaker-staging-web3/values.yaml"
)
for overlay in "${RB_OVERLAYS[@]}"; do
    echo "Validating charts/ragnarok-breaker with $overlay..."
    # 별도 할당으로 Helm 실패를 파이프 뒤의 kubeconform 성공이 가리지 않게 한다.
    RB_RENDERED=$(helm template --values "$overlay" "charts/ragnarok-breaker")
    printf '%s\n' "$RB_RENDERED" | ./kubeconform -strict -summary -skip "TCPRoute" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
