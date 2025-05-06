terraform {
  backend "gcs" {
    bucket = "k8s-standard-bucket-tfstate-1"
    # Use a unique prefix so this environment's state doesn't clash with others
    prefix = "terraform/state/internal"
  }
}
