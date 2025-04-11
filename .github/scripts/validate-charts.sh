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
