provider "google" {
  version     = "3.4.0"
  #project = var.project
  #region = var.region
  #zone = var.zone
}

data "google_client_config" "provider" {}
data "google_container_cluster" "quorumpreempt" {
  name = var.cluster_name
  location = var.location
  project = var.project
}

# It seems these modules can *only* be defined in main
module "workload-identity-kubeip" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "kubeip-sa"
  use_existing_k8s_sa = true
  namespace = "kube-system"
  project_id = var.project
}

module "quorum-node" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-node-sa"
  use_existing_k8s_sa = true
  namespace = "queth"
  project_id = var.project
}

module "workload-identity-dns01solver" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "dns01solver-sa"
  use_existing_k8s_sa = true
  namespace = "traefik"
  project_id = var.project
}

module "quorum-genesis" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-genesis-sa"
  use_existing_k8s_sa = true
  namespace = "queth"
  project_id = var.project
}

module "quorum-membership" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-membership-sa"
  use_existing_k8s_sa = true
  namespace = "queth"
  project_id = var.project
}

module "quorum-client" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-client-sa"
  use_existing_k8s_sa = true
  namespace = "caas"
  project_id = var.project
}

resource "google_project_service" "cloudresourcemanager" {
  project = var.project
  service = "cloudresourcemanager.googleapis.com"

  disable_dependent_services = true
}

resource "google_project_service" "iam" {
  project    = var.project
  service    = "iam.googleapis.com"
  depends_on = [google_project_service.cloudresourcemanager]

  disable_dependent_services = true
}

resource "google_project_service" "container" {
  project    = var.project
  service    = "container.googleapis.com"
  depends_on = [google_project_service.iam]

  disable_dependent_services = true
}

resource "google_container_cluster" "k8s" {
  provider           = google-beta
  name               = var.cluster_name
  project            = var.project
  depends_on         = [google_project_service.container]
  location           = var.location
  logging_service    = var.logging_service
  monitoring_service = var.monitoring_service

  # need to create a default node pool
  # delete this immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.gke-network.self_link
  subnetwork = google_compute_subnetwork.gke-subnet.self_link

  workload_identity_config {
    identity_namespace = "${var.project}.svc.id.goog"
  }
  private_cluster_config {
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_range_name
    services_secondary_range_name = var.services_range_name
  }
}

resource "google_storage_bucket" "cluster" {
  # requires that the cpe default service account is added as a delegated
  # owner at https://www.google.com/webmasters/verification
  # name = "${var.project}-cluster.${var.gcp_buckets_tld}"
  name = "${var.project}-${uuid()}"
  project = var.project
  # location is the 'region' here!
  location = var.region
  storage_class = "STANDARD"
}
