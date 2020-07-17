# Do these as a single map keyed resource so they can be indexed by secret id
# NOTICE: These need to be imported via terraform import, eg:
# terraform import \
#   module.cluster.google_secret_manager_secret.qnode[\"qnode-$i-$kind\"] \
#   projects/quorumpreempt/secrets/qnode-$i-$kind
resource "google_secret_manager_secret" "qnode" {
  project = var.project
  provider           = google-beta
  for_each = toset([
    "qnode-0-key", "qnode-0-enode",
    "qnode-0-wallet-address", "qnode-0-wallet-key", "qnode-0-wallet-password",
    "qnode-1-key", "qnode-1-enode",
    "qnode-1-wallet-address", "qnode-1-wallet-key", "qnode-1-wallet-password",
    "qnode-2-key", "qnode-2-enode",
    "qnode-2-wallet-address", "qnode-2-wallet-key", "qnode-2-wallet-password"
    ])
  secret_id = each.key
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_iam_member" "qnode-key" {
  project = var.project
  count = var.max_quorum_nodes
  provider           = google-beta
  secret_id = google_secret_manager_secret.qnode["qnode-${count.index}-key"].secret_id
  role = "roles/secretmanager.secretAccessor"
  member = module.quorum-node.gcp_service_account_fqn
}

resource "google_secret_manager_secret_iam_member" "qnode-enode" {
  project = var.project
  count = var.max_quorum_nodes
  provider           = google-beta
  secret_id = google_secret_manager_secret.qnode["qnode-${count.index}-enode"].secret_id
  role = "roles/secretmanager.secretAccessor"
  member = module.quorum-node.gcp_service_account_fqn
}

# managing these as secrets is more convenient for some things and not for
# others. wallet address are not sensitive at all, but doing it this way avoids
# having to stash them in resources we haven't created yet.
resource "google_secret_manager_secret_iam_member" "qnode-wallet" {
  project = var.project
  provider           = google-beta
  for_each = toset([
    "qnode-0-wallet-address", "qnode-0-wallet-key", "qnode-0-wallet-password",
    "qnode-1-wallet-address", "qnode-1-wallet-key", "qnode-1-wallet-password",
    "qnode-2-wallet-address", "qnode-2-wallet-key", "qnode-2-wallet-password"
    ])
  secret_id = each.key
  role = "roles/secretmanager.secretAccessor"
  member = module.quorum-client.gcp_service_account_fqn
}

# genesis puts wallet address in the genesis config. its easiest if it reads
# them direct from secretmanager.
resource "google_secret_manager_secret_iam_member" "qnode-wallet-addresses" {
  project = var.project
  provider           = google-beta
  for_each = toset([
    "qnode-0-wallet-address",
    "qnode-1-wallet-address",
    "qnode-2-wallet-address"
    ])
  secret_id = each.key
  role = "roles/secretmanager.secretAccessor"
  member = module.quorum-node.gcp_service_account_fqn
}
