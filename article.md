# Running quorum on preemptible GCP instances aka 'consortia ledger on the cheap'

## Intro

Run a cloud hosted 'consortia' style private dlt for less than £50 per month.
The deploymenent is aimed at developers wanting exposure to 'production'
tools & techniques without imposing 'production' costs (time and money)

Inspired by and extending [k8s for cheap on google cloud](https://dev.to/verkkokauppacom/how-to-kubernetes-for-cheap-on-google-cloud-1aei)

## What - overview

* quorum deployment with raft consensus and optional tessera (private transactions),
  with support for addition and removal of nodes at will.
  * raft is convenient and simple and scales 'enough' for development and small
    networks.
  * might leave tessera as follow up article.
* wallet keys held in GCP security-manager secrets access controled using GCP
  principals.
  * using Cloud KMS (hsm) backed key to wrap the secrets is possible but a
    *lot* more expensive and requires custom 'unwrap' code on the nodes
* Google Cloud NAT, Workload Identity, Secrets Manager
* kubeip and traefik for ingress
  * it is questionable whether kubeip is the right solution, it results in
    'un-assigned' ip pricing (>10x expensive but still only 24 cents/day). May
    be able to achieve the same results by simply assigning the ip to the
    ingress instance in the tf config - and lose kubeip altogether.
  * update my cost breakdown shows the static ip is the 2nd most expensive
    item. it is *more* expensive than some of my vm instances
* go-ethereum service exposing contract functions as rest endpoints.
* terraform cloud hosted and git controled cluster configuration.
* kubernetes pod authorisation using k8s service accounts bound to GCP
  principals using workload identity
  principals for kubernetes pod authorisation
* blob (bucket) storage for dlt configuration (genesis and static-nodes.json)
* blob (bucket) storage for tracking deployed contracts and their abi's
* skaffold for build/deploy/test

## Zero Cost at Idle (close as possible)

This may not be perfectly realizable. This is a list of things that affect it.

* Non-assigned static IP address are 10x more expensive than assigned.
  * If assigned by kubeip they are 'un-assigned' when the workload is deleted
  * If assigned to a vm instance they are 'un-assigned' whent the vm instance
    is deleted (cluster delete)
* PersistentVolumeClaim reclaim policy
  * For chain data this should really be Retain, but it will be retained after
    cluster deletion and that is >0 charge
* dns names if using

## How - fast

### cluster

* google cloud project setup
* tf cloud setup
* git commit

### Auth bootstrap (dev cli)

auth bootstrapping

    gcloud init (to set all the defaults)
    gcloud container clusters get-credentials kluster
    gcloud auth application-default login

### StatefulSet

* create templates with nginx ref examples
* update skaffold.yaml
* scaffold run

## Skaffold gotchas

* default setup almost just works. traefik taints only permit one instance so the
  replacement is stuck pending until the old instance is manually deleted.
* kubectl deployment needs extra work (or can't handle) dependence on customer
  resource definitions or definition order dependencies
  [order of manifest respected since aug 2019](https://github.com/GoogleContainerTools/skaffold/pull/2729)

## Network

TODO:

* static un-assigned ip address are way more expensive than assigned ones.
  kubeip might not be the best solution - but its still only 0.24 cents / day
* just assigning it to the ingress vm instance looks like the same effect and
  a lot less faff

We get a 'custom' [VPC Overview](https://cloud.google.com/vpc/docs/overview)

Point out how bits of the terrafor network configuration map to VPC

Consider Shared VPC for 'genesis' node

VPC Network Peering is the answer for SaaS and inter organisational
collaboration.

Hybrid cloud Cloud VPN is for self hosted *and* on-prem nodes

## Workloads

### Identity and Authorization

* anoyingly, workload-identity is currently incompatible with isio side car
  injection (at least without customisation)
* [Google - Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

The workspace-identity terraform modules create k8s service accounts with:

    automountServiceAccountToken: false

This is the secure default. pod's can set this explicitly if they need it. The
kubeip pod needs it. Once this is done, worload identity just works. No need
for GOOGLE_APPLICATION_CREDENTIALS or fetching tokens or epxlicitly managing
keys in secrets

Note it turns out that the google sdk client libraries "DefaultClient"
implementation are workload identity aware. Provided other established
mechanisms, such as GOOGLE_APPLICATION_CREDENTIALS, are not configured then it
falls through to just asking the metadata server for a token - at which point
it gets one.

test workload identity config:

    kubectl run -it \
      --generator=run-pod/v1 \
      --image google/cloud-sdk:slim \
      --serviceaccount quorum-node-sa \
      --namespace default workload-identity-test
    gcloud auth list

It will show the kluster-serviceaccount as the active account:

    kubectl run -it --generator=run-pod/v1 --image google/cloud-sdk:slim --serviceaccount quorum-node-sa --namespace default workload-identity-test
    gcloud auth print-identity-token


Get acccess token using curl:

    apt-get update && apt-get install jq -y
    TOKEN=$(curl -s -H 'Metadata-Flavor: Google' http://metadata/computeMetadata/v1/instance/service-accounts/default/token | jq -r .access_token)

Download:

    curl -H "Authorization: Bearer $TOKEN" https://storage.googleapis.com/storage/v1/b/quorumpreempt-cluster.g.buckets.thaumagen.com/o/hello.txt?alt=media

Upload:

    echo "hello workload" > hello.txt
    curl -X POST --data-binary @hello.txt \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: text/plain" \
        "https://storage.googleapis.com/upload/storage/v1/b/quorumpreempt-cluster.g.buckets.thaumagen.com/o?uploadType=media&name=hello.txt"

### Secrets

Terraforms posture on secret data in statefiles is [Stupid](https://github.com/hashicorp/terraform/issues/516)

Terraform cloud's posture is [Better](https://www.terraform.io/docs/state/sensitive-data.html) but far from ideal

With Google Secrets Manger the 'secret' and its 'version' are seperate things.
The 'version' is the current value of the 'secret'. IAM policies are applied to
the 'secret'. So, Use terraform to create the secret but use cli to set the
version version (current value) - that way tf never sees the secret data at all
but we can still use tf to manage the iam's for the secret

But note that the tfstate has credentials to access the whole project so its
still not a complete 'package'. Keys wrapped via Cloud KMS are probably the
'belt and braces' answer but that is too much cost & work for a developer
focused setup.

Dev guides [Google - Secret Manager](https://cloud.google.com/solutions/secrets-management#tools)

Using with terraform [Terraform and Secret Manager](https://www.sethvargo.com/managing-google-secret-manager-secrets-with-terraform/)

Note that we _do not_ create the secret with terraform as that exposes the
plain text in the state file. terrafor cloud encrypts that at rest but its
still not great.

#### Secret creation, terraform resource declaration & import

We pre-create a bunch of keys and set the IAM's 'before the show'. Remote State
and a TF project per node offers better granularity but a whole tf project per
node is pretty heavy weight. Pre-creation of 'light weight' resources doesn't
significantly impact our costs and is less faffy


Create the secrets for the nodes. This requires some setup.

See [requirements.txt](./tools/requirements.txt) and particularly
* [Python - google-auth](https://pypi.org/project/google-auth/)
* [Python - google-cloud-secret-manager](https://pypi.org/project/google-cloud-secret-manager/)

XXX: TODO: Sort out a docker image for this (and dind arrangements for linux and mac)

Run:

    gcloud auth application-default login

    scripts/secret.sh nodekey qnode-0
    scripts/secret.sh nodekey qnode-1
    scripts/secret.sh nodekey qnode-2

Create the tf resource in the cluster module

    resource "google_secret_manager_secret" "qnode" {
      for_each = toset([
        "qnode-0-key", "qnode-0-enode",
        "qnode-1-key", "qnode-1-enode",
        "qnode-2-key", "qnode-2-enode" ])
      secret_id = each.key
      replication = automatic
    }

Select appropriate version of beta provider in terraform.tf

    required_providers {
      google-beta = ">= 3.8"
    }

    terraform init  # to update provider if necessary can ommit

Import the secret defintions

    terraform import -provider=google-beta \
        module.cluster.google_secret_manager_secret.qnode-enode[\"qnode-0-enode\"] \
        projects/quorumpreempt/secrets/qnode-0-enode

Now go look at the contents of your tf state and convince yourself that the
(public) enode address is not revlealed

Now import the rest - do both the keys and th enodes now we know the keys wont
get dumped into the tfstate.

    terraform import -provider=google-beta \
        module.cluster.google_secret_manager_secret.qnode-enode[\"qnode-0-key\"] \
        projects/quorumpreempt/secrets/qnode-0-key

    for i $(seq 1 2)
    do
        terraform import -provider=google-beta \
            module.cluster.google_secret_manager_secret.qnode-enode[\"qnode-$i-enode\"] \
            projects/quorumpreempt/secrets/qnode-$i-key
        terraform import -provider=google-beta \
            module.cluster.google_secret_manager_secret.qnode-enode[\"qnode-$i-key\"] \
            projects/quorumpreempt/secrets/qnode-$i-enode
    done

So we need to import the state

[Terraform - Import](https://www.terraform.io/docs/import/index.html)
[Terraform - Import Secret](https://www.terraform.io/docs/providers/google/r/secret_manager_secret.html#import)

init container with service principal auth to get token.
use curl to get secret via api

    TOKEN=$(curl -s -H 'Metadata-Flavor: Google' http://metadata/computeMetadata/v1/instance/service-accounts/default/token | jq -r .access_token)
    curl "https://secretmanager.googleapis.com/v1/projects/quorumpreempt/secrets/quorum-0-key/versions/1:access" \
        --request "GET" \
        --header "authorization: Bearer ${TOKEN}" \
        --header "content-type: application/json" \
        --header "x-goog-user-project: quorumpreempt"

We store enode address alongside the key for convenience even though it is not
secret - saves faffing with two different storage providers or having to
re-derive the enode addr

The init container gets the key every time - incase it roles. Caches most
recent key on local disc. Two modes of operation:

1. dev - if the key changes, force re-create the node (saving the old node
   dir). maximum convenience for dev, not much risk to chain data
2. prod - if key changes, refuse to start

See also,
* If you can afford it [Google KMS](https://medium.com/kudos-engineering/secret-management-in-kubernetes-and-gcp-the-journey-c76da8de96d8)
* From the makers of kubeip [secrets-init](https://blog.doit-intl.com/kubernetes-and-secrets-management-in-cloud-858533c20dca)
  Integrates with Google Secrets Manager and Google Workload Identity
Glossy [Google - Secret Manager](https://cloud.google.com/secret-manager)

### Protocol Selection (Istio Compatibility) Ports and IP Assignment

If considering adding istio to the mix, port names matter if deploying on k8s <
1.18. [Istio - Protocol Selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/)

In this article, and for the supporting git hub manifest all ports are named
with this in mind

All ports are set consistently with the defaults for the workload service. So
8545 is the json-rpc port for qurourms workload. To support routing to multiple
quorum instances in the same cluster from the public internet through a *single
ip* address we shift the port assignments in blocks of 10. So the first node
has all defaults, the second has default + 10 and so on. This is a cost/ease
concession.

When ip addresses are not assigned, the cost 10x more. And for a developer
focused deployment we expect tearing down workloads and leaving the cluster
idle to be the norm. If ips are persistently assigned to vm instances the idle
costs would be acceptable. But then tearing down the cluster would actually
*increase* our costs over an  idle cluster. Idealy we want tearning down the
cluster to reduce our monthly google bill to zero.

We can the use the magic of terraform cloud to stand everything up again in
'cup of coffee' time frame.

### Storage for chain nodes

* persistent disc on vm for chain data
* persistent disc on vm for tessera db (anything else is $$$)
* blob storage in bucket for genesis, network membership (static-nodes) and
  node config.

#### Resources - Perstent Volumes, StatefulSets, Istio (StatefulSets not really supported)

* [Google Cloud, PersistentVolumeClaim](https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes)
* [Google Cloud, StatefulSet](https://cloud.google.com/kubernetes-engine/docs/concepts/statefulset)

Reclaim policy to retain after claim gone ? [k8s pv reclaim policy](https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/)
This has to be done by directly modifying the Persistent Voluem *after* it has
been provisioned. See [change reclaim policy on a dynamically provissioned volume](https://kubernetes.io/blog/2017/03/dynamic-provisioning-and-storage-classes-kubernetes/)

> StatefulSets use an ordinal index for the identity and ordering of their
> Pods. By default, StatefulSet Pods are deployed in sequential order and are
> terminated in reverse ordinal order
-- [Google Cloud, StatefulSet](https://cloud.google.com/kubernetes-engine/docs/concepts/statefulset)

Parallel should be fine, although the default OrderedReady may be more
convenient it encourages un-necessary order dpendency.

It may prove tempting to use a Deployment and ReadWriteOnce with a single node.
This isn't a reliable configuration. See [Google - Deployment vs StatefulSets](https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes#deployments_vs_statefulsets)

A StatefulSet with a single replica is the right choice for scenarious where a
single helm deployment equates to a single dlt node.

Without Istio in play, our setup enables use of kubectl scale to dynamicaly
increase the node count.

updateStragety (statefulset)

For RollingUpdate a onfig change starts a new pod. The old pod is only deleted
once the new one is up and ready.

??? If the new pod is re-using the node key of the old this will/will not work ?

For OnDelete, a manual pod deletion triggers a new pod to be created.

??? Individual node key delivery to pods in stateful set ?

Istio users beware, istio has ambigious (at best) support for StatefulSet
applications. In short, if the nodes are *NOT EXTERNALY EXPOSED* then it is
possible to have them 'in mesh' without much trouble. If the are to be routable
accross the open internet, it is still possible, but explicit istio
configuration needs to be created for each scaled instance of the StatefulSet.

If external clients usage is agnostic to which quorum instance they talk
to, it is actually ok to let istio lb the traffict. This works pretty well
until tessera is added - at which point using raw transactions (as go-ethereum
clients do) make things quite hairy. The tx needs to be submited first to
tessera then its hash presented to quorum in a seperate request. There are ways
to make it rare that those request pairs will reach different services but it
will still happen.

And tessera instances MUST be able to reliably reach specific peers else they
will refuse to ACK transactions.

This article on casandra has the key points layed out very well
if using ClusterIP: None (headless) and where only internal routing is required
(No north/south from external sources)

[Cassandra / Istio Article](https://aspenmesh.io/running-stateless-apps-with-service-mesh-kubernetes-cassandra-with-istio-mtls-enabled/)
* Congigure container processes (qurorum) to listen on local host (despite
    recording externaly visible ip/hosts in static-nodes.json)
* REMOVE/DON'T ADD ServiceEntry's or VirtualService definitions
* For ClusterIP: None, the default load balancing mode is PASSTHROUGH

This article covers North/South. Essentially, a manualy, or some how templated,
ServiceEntry, Gateway and VirtualService are required for *each individual pod*
in the statefulset -- this is a problem for using kubectl scale 'on the flye'
[Istio, Headless Services, StatefulSet](https://medium.com/airy-science/making-istio-work-with-kubernetes-statefulset-and-headless-services-d5725c8efcc9)

This will wrap traffic in mTLS. Note that as quorum now supports rpc over tls
this may not be as compelling any more.

[Istio, Headless Services, StatefulSet](https://medium.com/airy-science/making-istio-work-with-kubernetes-statefulset-and-headless-services-d5725c8efcc9)
[Istio ticket statefulset not supported](https://github.com/istio/istio/issues/10659)
[Cassandra / Istio Article](https://aspenmesh.io/running-stateless-apps-with-service-mesh-kubernetes-cassandra-with-istio-mtls-enabled/)

## Quorum

TODO:

* standup vanila pod with pvc
* deliver nodekey to pod using workload identity
* deliver wallet key to pod using (ideally different) workload identity
* store pods configuration in blob object named after its public key
* do gensis
* do member add

## Article Resources

* Inspired by [k8s for cheap on google cloud](https://dev.to/verkkokauppacom/how-to-kubernetes-for-cheap-on-google-cloud-1aei)