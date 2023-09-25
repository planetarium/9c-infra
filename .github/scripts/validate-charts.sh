find . -type d -name templates -print | while read -r dir
do
    chart_dir=$(dirname "$dir")
    echo "Validating $chart_dir..."
    helm lint "$chart_dir" || exit 1
    helm template "$chart_dir" | ./kubeconform -summary -skip "ExternalSecret,SecretStore,Secret" || exit 1
done
