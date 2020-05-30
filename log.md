2020-05-30
----------

Object storage.

Verify ownership of a domain for bucket name OR use a UUID

If using UUID to name a bucket, labels can be used to identify.

bucket properties
name: quorumpreempt-cluster.g.buckets.thaumangen.com
name: quorumpreempt-nodes.g.buckets.thaumangen.com
name: quorumpreempt-node-{n}.g.buckets.thaumangen.com

location: europe-west2 (london)
storage-class: standard (hot &or short term)

object versioning ?
"when you overwrite an object," , the old object is replaced with the new. With
versioning, the previous versions are available - probably use this for
contract address storage. Is 'overwrite' implied by any 'edit' ? YES objects
are IMUTABLE
* https://cloud.google.com/storage/docs/generations-preconditions#_Preconditions

Also, 'create-only-if-new' precondition match on generation 0

* https://cloud.google.com/storage/docs/creating-buckets
* https://cloud.google.com/storage/docs/domain-name-verification
*

ACLs vs Cloud IAM
* https://cloud.google.com/storage/docs/uniform-bucket-level-access


2020-05-16
----------
Error setting IAM policy for service account ... Identity namespace does not
exist <project>.svc.id.goog

Means workload identity is not enabled on the cluster. Enabling after the fact
in terraform using workload_identity_config doesn't appear to work. 

`gcloud container clusters update --region europe-west2-a kluster --workload-pool=quorumpreempt.svc.id.goog`


* https://www.terraform.io/docs/providers/google/r/container_cluster.html#workload_identity_config
* https://medium.com/google-cloud/bootstrapping-google-kubernetes-engine-after-creating-it-dca595f830a1
* https://www.terraform.io/docs/providers/google/guides/using_gke_with_terraform.html
* https://learn.hashicorp.com/terraform/kubernetes/provision-gke-cluster

Waiting seems to be the anser to being stuck 'preparing plan'

Though also ensured the following envs were set

TF_CLI_CONFIG_FILE=/Users/robin/jitsuin/quorum-gcp-preemptible/dotterraformrc
GOOGLE_CLOUD_KEYFILE_JSON=/Users/robin/jitsuin/quorum-gcp-preemptible/credentials/terraform/gcp-terrraform-compute-api.json

Preparing the remote plan...

To view this run in a browser, visit:
https://app.terraform.io/app/robinbryce/consortia-quorum-preempt/runs/run-Nyx2mb5eqg4CCjyC

Waiting for the plan to start...

Terraform v0.12.18
Configuring remote state backend...
Initializing Terraform configuration...
2020/05/15 20:51:49 [DEBUG] Using modified User-Agent: Terraform/0.12.18 TFC/ba6190e398
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.

module.cluster.google_compute_address.static-ingress: Refreshing state... [id=projects/quorumpreempt/regions/europe-west2/addresses/static-ingress]
module.cluster.google_project_service.cloudresourcemanager: Refreshing state... [id=quorumpreempt/cloudresourcemanager.googleapis.com]
module.cluster.module.quorumpreempt-workload-identity.google_service_account.cluster_service_account: Refreshing state... [id=projects/quorumpreempt/serviceAccounts/quorumpreempt-sa@quorumpreempt.iam.gserviceaccount.com]
module.cluster.google_compute_network.gke-network: Refreshing state... [id=projects/quorumpreempt/global/networks/kluster]
module.cluster.module.quorumpreempt-workload-identity.module.annotate-sa.random_id.cache: Refreshing state... [id=-VT2HA]
module.cluster.google_compute_firewall.default: Refreshing state... [id=projects/quorumpreempt/global/firewalls/web-ingress]
module.cluster.google_compute_subnetwork.gke-subnet: Refreshing state... [id=projects/quorumpreempt/regions/europe-west2/subnetworks/kluster]
module.cluster.google_compute_router.gke-router: Refreshing state... [id=projects/quorumpreempt/regions/europe-west2/routers/kluster]
module.cluster.google_compute_router_nat.gke-nat: Refreshing state... [id=quorumpreempt/europe-west2/kluster/kluster]
module.cluster.google_project_service.iam: Refreshing state... [id=quorumpreempt/iam.googleapis.com]
module.cluster.google_project_service.container: Refreshing state... [id=quorumpreempt/container.googleapis.com]
module.cluster.google_project_iam_custom_role.kluster: Refreshing state... [id=projects/quorumpreempt/roles/kluster]
module.cluster.google_project_iam_custom_role.kubeip: Refreshing state... [id=projects/quorumpreempt/roles/kubeip]
module.cluster.google_service_account.kubeip: Refreshing state... [id=projects/quorumpreempt/serviceAccounts/kubeip-serviceaccount@quorumpreempt.iam.gserviceaccount.com]
module.cluster.google_service_account.kluster: Refreshing state... [id=projects/quorumpreempt/serviceAccounts/kluster-serviceaccount@quorumpreempt.iam.gserviceaccount.com]
module.cluster.google_project_iam_member.iam_member_kubeip: Refreshing state... [id=quorumpreempt/projects/quorumpreempt/roles/kubeip/serviceaccount:kubeip-serviceaccount@quorumpreempt.iam.gserviceaccount.com]
module.cluster.google_project_iam_member.iam_member_kluster: Refreshing state... [id=quorumpreempt/projects/quorumpreempt/roles/kluster/serviceaccount:kluster-serviceaccount@quorumpreempt.iam.gserviceaccount.com]
module.cluster.google_container_cluster.k8s: Refreshing state... [id=projects/quorumpreempt/locations/europe-west2-a/clusters/kluster]
module.cluster.google_container_node_pool.custom_nodepool["ingress-pool"]: Refreshing state... [id=projects/quorumpreempt/locations/europe-west2-a/clusters/kluster/nodePools/ingress-pool]
module.cluster.google_container_node_pool.custom_nodepool["work-pool"]: Refreshing state... [id=projects/quorumpreempt/locations/europe-west2-a/clusters/kluster/nodePools/work-pool]

------------------------------------------------------------------------

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.cluster.module.quorumpreempt-workload-identity.google_service_account_iam_member.main will be created
  + resource "google_service_account_iam_member" "main" {
      + etag               = (known after apply)
      + id                 = (known after apply)
      + member             = "serviceAccount:quorumpreempt.svc.id.goog[default/quorumpreempt-sa]"
      + role               = "roles/iam.workloadIdentityUser"
      + service_account_id = "projects/quorumpreempt/serviceAccounts/quorumpreempt-sa@quorumpreempt.iam.gserviceaccount.com"
    }

  # module.cluster.module.quorumpreempt-workload-identity.kubernetes_service_account.main[0] will be created
  + resource "kubernetes_service_account" "main" {
      + default_secret_name = (known after apply)
      + id                  = (known after apply)

      + metadata {
          + annotations      = {
              + "iam.gke.io/gcp-service-account" = "quorumpreempt-sa@quorumpreempt.iam.gserviceaccount.com"
            }
          + generation       = (known after apply)
          + name             = "quorumpreempt-sa"
          + namespace        = "default"
          + resource_version = (known after apply)
          + self_link        = (known after apply)
          + uid              = (known after apply)
        }
    }

Plan: 2 to add, 0 to change, 0 to destroy.
Robins-MacBook-Pro:quorum-gcp-preemptible robin$ TF_LOG=1 terraform plan


static network, membership addition (removal?) possible
=======================================================





Signup for terraform.io cloud.


https://dev.to/verkkokauppacom/how-to-kubernetes-for-cheap-on-google-cloud-1aei


Use personal git hub, restrict to single repository.

./install.sh --rc-path ~/.bashrc --path-update ~/.bash_profile

* Terraform Cloud nees enable google compute engine api enabled
* To use terraform to enable services, enable the service usage api
*
* £45 PCM 3x n1-standard-2 pre-emptible  (2x vCPU + 7.5 GB RAM)
* £ 5 PCM 2x f1-micro
