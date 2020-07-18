
# -----------------------------------------------------------------------------
# cluster service account and role
# -----------------------------------------------------------------------------
resource "google_project_iam_custom_role" "kluster" {
  role_id = "kluster"
  title   = "kluster Role"

  project    = var.project
  depends_on = [google_project_service.iam]

  permissions = [
    "compute.addresses.list",
    "compute.instances.addAccessConfig",
    "compute.instances.deleteAccessConfig",
    "compute.instances.get",
    "compute.instances.list",
    "compute.projects.get",
    "container.clusters.get",
    "container.clusters.list",
    "resourcemanager.projects.get",
    "compute.networks.useExternalIp",
    "compute.subnetworks.useExternalIp",
    "compute.addresses.use",
    "resourcemanager.projects.get",
    "storage.objects.get",
    "storage.objects.list",
  ]
}

# This exists to enable output variables to be added without changing other
# resources
# * [issue](https://github.com/hashicorp/terraform/issues/22607) remains open.
# * [Workaround](https://support.hashicorp.com/hc/en-us/articles/360000958148-Terraform-outputs-fail-to-update-in-Terraform-Enterprise)
resource "null_resource" "n" {}

resource "google_service_account" "kluster" {

  account_id = "kluster-serviceaccount"
  project    = var.project
  depends_on = [google_project_iam_custom_role.kluster]
}

resource "google_project_iam_member" "iam_member_kluster" {

  role       = "projects/${var.project}/roles/kluster"
  project    = var.project
  member     = "serviceAccount:kluster-serviceaccount@${var.project}.iam.gserviceaccount.com"
  depends_on = [google_service_account.kluster]
}
