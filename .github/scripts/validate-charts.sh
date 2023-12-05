find . -type d -name templates -print | while read -r dir
do
    chart_dir=$(dirname "$dir")
    echo "Validating $chart_dir..."
    helm lint "$chart_dir" || exit 1
    helm template "$chart_dir" | ./kubeconform -summary -skip "ExternalSecret,SecretStore,Secret" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' || exit 1
done

# Check multiplanetary networks manually
CLUSTERS=("9c-main" "9c-internal")
NETWORKS=("9c-network" "heimdall" "idun")
for cluster in "${CLUSTERS[@]}"; do
    for network in "${NETWORKS[@]}"; do
        helm template --values "$cluster/multiplanetary/network/$network.yaml" \
            --values "$cluster/multiplanetary/network/general.yaml" \
            "charts/all-in-one" | ./kubeconform -summary -skip "ExternalSecret,SecretStore,Secret" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' || exit 1s
    done
done
