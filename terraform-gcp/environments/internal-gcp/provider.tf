provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file("/path/to/service-account.json")
}