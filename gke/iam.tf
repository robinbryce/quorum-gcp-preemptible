
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

# -----------------------------------------------------------------------------
# kubeip service account and role
# -----------------------------------------------------------------------------
resource "google_project_iam_custom_role" "kubeip" {
  role_id = "kubeip"
  title   = "kubeip Role"

  project    = var.project
  depends_on = [google_project_service.iam]


  permissions = [
    "compute.addresses.list",
    "compute.instances.addAccessConfig", "compute.instances.deleteAccessConfig",
    "compute.instances.get",
    "compute.instances.list",
    "compute.projects.get",
    "container.clusters.get",
    "container.clusters.list",
    "resourcemanager.projects.get",
    "compute.networks.useExternalIp",
    "compute.subnetworks.useExternalIp",
    "compute.addresses.use",
  ]
}

resource "google_service_account" "kubeip" {
  account_id = "kubeip-serviceaccount"
  project    = var.project
  depends_on = [google_project_iam_custom_role.kubeip]
}

resource "google_project_iam_member" "iam_member_kubeip" {

  role       = "projects/${var.project}/roles/kubeip"
  project    = var.project
  member     = "serviceAccount:kubeip-serviceaccount@${var.project}.iam.gserviceaccount.com"
  depends_on = [google_service_account.kubeip]
}

# -----------------------------------------------------------------------------
# cluster storage bucket iam bindings
# -----------------------------------------------------------------------------

# Set the appropriate iam member and roles for quourm service account. This is additive
#
# Consider using - https://github.com/terraform-google-modules/terraform-google-iam/tree/master/modules/storage_buckets_iam
# * https://cloud.google.com/iam/docs/overview
# * https://www.terraform.io/docs/providers/google/r/storage_bucket_iam.html
# Notes
# * policy - setting the *whole* policy clobbers any existing policy already on the
#   resource - hence google_storage_bucket_iam_policy is a bit of a shotgun/foot.
# * binding - sets *all* members (discarding previous) for a particular role.
#   After application, any previous members are dropped. no other (previous) members 
# * member - not authorative (additive)
resource "google_storage_bucket_iam_member" "cluster_bucket_quorum_members" {
  for_each = {
    genesis_objectadmin = ["roles/storage.objectAdmin", "${module.quorum-genesis.gcp_service_account_fqn}"]
    membership_objectadmin = ["roles/storage.objectAdmin", "${module.quorum-membership.gcp_service_account_fqn}"]
    genesis_objectview = ["roles/storage.objectViewer", "${module.quorum-genesis.gcp_service_account_fqn}"]
    membership_objectview = ["roles/storage.objectViewer", "${module.quorum-membership.gcp_service_account_fqn}"]
    node_objectview = ["roles/storage.objectViewer", "${module.quorum-node.gcp_service_account_fqn}"]
    client_objectview = ["roles/storage.objectViewer", "${module.quorum-client.gcp_service_account_fqn}"]
  }
  bucket = google_storage_bucket.cluster.name
  role = each.value[0]
  member = each.value[1]
}
