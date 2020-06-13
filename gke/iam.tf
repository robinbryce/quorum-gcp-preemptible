
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
resource "google_storage_bucket_iam_binding" "cluster_bucket_project_members_admin" {
  bucket = google_storage_bucket.cluster.name
  role = "roles/storage.objectAdmin"
  members = var.members_bucket_admins
}

resource "google_storage_bucket_iam_binding" "cluster_bucket_project_members_view" {
  bucket = google_storage_bucket.cluster.name
  role = "roles/storage.objectViewer"
  members = var.members_bucket_admins
}

# bind the quorum-genesis sa to the policy for the cluster bucket.
# * https://cloud.google.com/iam/docs/overview
# * https://www.terraform.io/docs/providers/google/r/storage_bucket_iam.html
# Note setting the *whole* policy clobbers any existing policy already on the
# resource - hence google_storage_bucket_iam_policy is a bit of a shotgun and
# binding is prefered as it is additive.
#resource "google_storage_bucket_iam_binding" "cluster_bucket_quorum_members_admin" {
#  bucket = google_storage_bucket.cluster.name
#  role = "roles/storage.objectAdmin"
#  members = [
#    "${module.quorum-genesis.gcp_service_account_fqn}",
#    "${module.quorum-membership.gcp_service_account_fqn}"
#  ]
#}
#
#resource "google_storage_bucket_iam_binding" "cluster_bucket_quorum_members_view" {
#  bucket = google_storage_bucket.cluster.name
#  role = "roles/storage.objectViewer"
#  members = [
#    "${module.quorum-genesis.gcp_service_account_fqn}",
#    "${module.quorum-membership.gcp_service_account_fqn}",
#    "${module.quorum-node.gcp_service_account_fqn}",
#    "${module.quorum-client.gcp_service_account_fqn}"
#  ]
#}
