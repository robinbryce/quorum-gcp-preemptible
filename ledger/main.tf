variable "cluster_workspace" {
  type = string
  default = "cluster"
}

variable "cluster_name" {
    type = string
    default = "kluster"
}

provider "random" {}

provider "null" {}

provider "google" {
  version     = "3.4.0"
  #project = data.terraform_remote_state.cluster.outputs.gcp_project_id
  project = "ledger-2"
}

data "terraform_remote_state" "cluster" {
  backend = "remote"
  config = {
    organization = "robinbryce"
    workspaces = {
      # name = "ledger-2"
      name = var.cluster_workspace
    }
  }
}

provider "kubernetes" {
  load_config_file = "false"
  host = "https://${data.google_container_cluster.quorumpreempt.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.quorumpreempt.master_auth[0].cluster_ca_certificate,
  )
}

data "google_client_config" "provider" {}
data "google_container_cluster" "quorumpreempt" {
  name = var.cluster_name
  project = data.terraform_remote_state.cluster.outputs.gcp_project_id
  location = data.terraform_remote_state.cluster.outputs.gcp_project_zone
}
