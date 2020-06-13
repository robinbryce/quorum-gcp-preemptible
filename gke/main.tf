module "quorumpreempt-workload-identity" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorumpreempt-sa"
  namespace = "default"
  project_id = var.project
}

module "quorum-genesis" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-genesis-sa"
  namespace = "default"
  project_id = var.project
}

module "quorum-membership" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-membership-sa"
  namespace = "default"
  project_id = var.project
}

module "quorum-node" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-node-sa"
  namespace = "default"
  project_id = var.project
}

module "quorum-client" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "7.3.0"
  name = "quorum-client-sa"
  namespace = "default"
  project_id = var.project
}

provider "google" {
  version     = "3.4.0"
#  credentials = var.gcp_compute_api_key
}

#provider "google-beta" {
#   version     = "3.5.0"
##   credentials = var.gcp_compute_api_key
#}

data "google_client_config" "provider" {}
data "google_container_cluster" "quorumpreempt" {
  name = var.cluster_name
  location = var.location
  project = var.project
}

provider "kubernetes" {
  load_config_file = false
  host = "https://${data.google_container_cluster.quorumpreempt.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.quorumpreempt.master_auth[0].cluster_ca_certificate,
  )
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
    identity_namespace = "${data.google_container_cluster.quorumpreempt.project}.svc.id.goog"
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
  name = "${var.project}-cluster.${var.gcp_buckets_tld}"
  # quorumpreempt-cluster.g.buckets.thaumagen.com | shasum
  # name = "b9f115a33a0ff161cc64aa79b35fd2005c6859ce"
  project = var.project
  # location is the 'region' here!
  location = var.region
  storage_class = "STANDARD"
}

# bind the quorum-genesis sa to the policy for the cluster bucket.
# * https://cloud.google.com/iam/docs/overview
# * https://www.terraform.io/docs/providers/google/r/storage_bucket_iam.html
# Note setting the *whole* policy clobbers any existing policy already on the
# resource - hence google_storage_bucket_iam_policy is a bit of a shotgun and
# binding is prefered as it is additive.
resource "google_storage_bucket_iam_binding" "cluster_bucket_members_admin" {
  bucket = google_storage_bucket.cluster.name
  role = "roles/storage.objectAdmin"
  members = concat(
    var.members_bucket_admins, [
    "${module.quorum-genesis.gcp_service_account_fqn}",
    "${module.quorum-membership.gcp_service_account_fqn}"
  ])
}

resource "google_storage_bucket_iam_binding" "cluster_bucket_members_view" {
  bucket = google_storage_bucket.cluster.name
  role = "roles/storage.objectViewer"
  members = concat(
    var.members_bucket_admins, [
    "${module.quorum-genesis.gcp_service_account_fqn}",
    "${module.quorum-membership.gcp_service_account_fqn}",
    "${module.quorum-node.gcp_service_account_fqn}",
    "${module.quorum-client.gcp_service_account_fqn}"
  ])
}

#data "google_iam_policy" "cluster_bucket_object_reader" {
## roles/storage.objectViewer
#}

