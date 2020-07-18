locals {
  gcp_project_sa_fqn = "serviceAccount:${data.terraform_remote_state.cluster.outputs.gcp_project_id}.svc.id.goog"
  gcp_project_id = data.terraform_remote_state.cluster.outputs.gcp_project_id
}

#resource "google_service_account" "kubeip" {
#  account_id   = "kubeip"
#  display_name = substr("Workload Identity ${local.gcp_project_sa_fqn}[kube-system/kubeip]", 0, 100)
#  project      = local.gcp_project_id
#}
#
#resource "google_service_account_iam_member" "kubeip_workload" {
#  service_account_id = google_service_account.kubeip.name
#  role               = "roles/iam.workloadIdentityUser"
#  member             = "${local.gcp_project_sa_fqn}[kube-system/kubeip]"
#}

# the kubernets service accounts must ALL be created and anotated like this
# (but change kubeip to be the account_id of the sa)
#    annotations = {
#      "iam.gke.io/gcp-service-account" = google_service_account.kubeip.email
#    }

#resource "google_service_account" "dns01solver-sa" {
#  account_id   = "dns01solver-sa"
#  display_name = substr("Workload Identity ${local.gcp_project_sa_fqn}[traefik/dns01solver-sa]", 0, 100)
#  project      = local.gcp_project_id
#}
#
#resource "google_service_account_iam_member" "dns01solver-sa_workload" {
#  service_account_id = google_service_account.dns01solver-sa.name
#  role               = "roles/iam.workloadIdentityUser"
#  member             = "${local.gcp_project_sa_fqn}[traefik/dns01solver-sa]"
#}

resource "google_service_account" "workloads" {
  for_each = {
    kubeip = ["kube-system", "kubeip-sa"]
    dns01solver = ["traefik", "dns01solver-sa"]
    queth_genesis = ["queth", "quorum-genesis-sa"]
    queth_node = ["queth", "quorum-node-sa"]
    queth_membership = ["queth", "quorum-membership-sa"]
    queth_client = ["queth", "quorum-client-sa"]
  }
  account_id   = each.value[1]
  display_name = substr("Workload Identity ${local.gcp_project_sa_fqn}[${each.value[0]}/${each.value[1]}]", 0, 100)
  project      = local.gcp_project_id
}

resource "google_service_account_iam_member" "workloads" {
  for_each = {
    kubeip = ["kube-system", "kubeip-sa"]
    dns01solver = ["traefik", "dns01solver-sa"]
    queth_genesis = ["queth", "quorum-genesis-sa"]
    queth_node = ["queth", "quorum-node-sa"]
    queth_membership = ["queth", "quorum-membership-sa"]
    queth_client = ["queth", "quorum-client-sa"]
  }

  service_account_id = google_service_account.workloads[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.gcp_project_sa_fqn}[${each.value[0]}/${each.value[1]}]"
}
