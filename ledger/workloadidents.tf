#resource "null_resource" "kubectl" {
#  # change trigger to run every time
#  triggers = {
#    build_number = "${timestamp()}"
#  }
#
#  # download kubectl
#  provisioner "local-exec" {
#    command = "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl"
#  }
#
#  # run kubectl
#  #provisioner "local-exec" {
#  #  command = "./kubectl apply -f deployment.yaml"
#  #}
#}

locals {
  gcp_project_sa_fqn = "serviceAccount:${data.terraform_remote_state.cluster.outputs.gcp_project_id}.svc.id.goog"
  gcp_project_id = data.terraform_remote_state.cluster.outputs.gcp_project_id
}

resource "google_service_account" "kubeip" {
  account_id   = "kubeip"
  display_name = substr("Workload Identity ${local.gcp_project_sa_fqn}[kube-system/kubeip]", 0, 100)
  project      = local.gcp_project_id
}

resource "google_service_account_iam_member" "kubeip_workload" {
  service_account_id = google_service_account.kubeip.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.gcp_project_sa_fqn}[kube-system/kubeip]"
}

# the kubernets service account must be created and anotated as
#    annotations = {
#      "iam.gke.io/gcp-service-account" = google_service_account.kubeip_gsa.email
#    }
