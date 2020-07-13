provider "google" {
  version     = "3.4.0"
}

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

# cargo culted from https://stackoverflow.com/questions/58232731/kubectl-missing-form-terraform-cloud
resource "null_resource" "custom" {
  # change trigger to run every time
  triggers = {
    build_number = "${timestamp()}"
  }

  # download kubectl
  provisioner "local-exec" {
    command = "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl"
  }

  # run kubectl
  #provisioner "local-exec" {
  #  command = "./kubectl apply -f deployment.yaml"
  #}
}

# This describes all the workload identities and there respective
# namespaces
# 
# Creating k8s namespaces from terraform feels like a layering violation.
# However, the 'canned' workload identity support needs to create the account
# or use a pre-existing one. Possibly the right thing is to split off the
# cluster & networking terraform from the ingresss 'edge', 'iam' and 'service'
# supporting terraform. For now we create the namespaces we need to support the
# desired workload identity distinctions
#
# The current identity namespaces are:
# * traefik - dns01 challenge resolution cloud dns access
# * queth - genesis and dlt network configuration. storage bucket read/write and raft add/remove and reading node keys
# * caas - contracts layer, reading account keys (secrets)

# This namespace gets the identity that can resolve dns challenges. This
# idenity can create and delete dns records
resource "kubernetes_namespace" "traefik" {
  metadata {
    labels = { name = "traefik" }
    name = "traefik"
  }
}

# All the quorum nodes go in here. We don't segregate them further. Any node
# could potentially do genesis (writing to the storage bucket) and perform raft
# add/remove. That could be finessed. But this seems enough for a developer
# oriented setup.
resource "kubernetes_namespace" "queth" {
  metadata {
    labels = { name = "queth" }
    name = "queth"
  }
}

# Can read wallet account keys
resource "kubernetes_namespace" "caas" {
  metadata {
    labels = { name = "caas" }
    name = "caas"
  }
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
