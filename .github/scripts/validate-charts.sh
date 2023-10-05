find . -type d -name templates -print | while read -r dir
do
    chart_dir=$(dirname "$dir")
    echo "Validating $chart_dir..."
    helm lint "$chart_dir" || exit 1
    helm template "$chart_dir" | ./kubeconform -summary -skip "ExternalSecret,SecretStore,Secret" -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' || exit 1
done
