# Running quorum on preemptible GCP instances aka 'consortia ledger on the cheap'
Stuff that probably isn't worth writing up but which may be a handy reference

* 2nd envoy to do grpc transcoding https://www.envoyproxy.io/docs/envoy/v1.9.0/configuration/http_filters/grpc_json_transcoder_filter

## What - overview

* quorum
  * using Cloud KMS (hsm) backed key to wrap the secrets is possible but a
    *lot* more expensive and requires custom 'unwrap' code on the nodes
  * can't avoid node keys on disc (clef can fix this?), but can make it
    transitory and ram based
  * could (probably) avoid wallet keys on disc - or at least puting them on
    disc ourselves - but its more work. currently, and this is normal when
    using go-ethereum based clients - clients all sign and send raw tx's. don't
    think clef is compatible with this.
* kubeip, envoy and traefik
  * it is questionable whether kubeip is the right solution, it results in
    'un-assigned' ip pricing (>10x expensive but still only 24 cents/day). May
    be able to achieve the same results by simply assigning the ip to the
    ingress instance in the tf config - and lose kubeip altogether.
  * update my cost breakdown shows the static ip is the 2nd most expensive
    item. it is *more* expensive than some of my vm instances

## Switching it all over from kubectl to kustomize

[argo cd's thoughts](https://blog.argoproj.io/the-state-of-kubernetes-configuration-management-d8b06c1205)
[helm-vs-kustomize](https://medium.com/@alexander.hungenberg/helm-vs-kustomize-how-to-deploy-your-applications-in-2020-67f4d104da69)

There is NO AVOIDING some kind of templatization - resitance is futile. But
helm and its chart repository model don't suit all use cases. Especially not
rapid developer prototyping: See [argo cd's thoughts](https://blog.argoproj.io/the-state-of-kubernetes-configuration-management-d8b06c1205)

The idea of kustomize is solid, having manifests I can deploy directly is a
*huge* win. But there are always a few details that need substituting. sed and
envsubst are venerable and often completely adequate solutions for *seed*
customization. The get hairy fast when they are embeded in daily workflow.

For this project, we templatize the kustomizations that are most deplendent on
the repository owner: google project name, deployment domain name. We use
templating to *seed* the kustomization's in a new repository and *commit* the
results. A bootstraping step in otherwords. This suites the purpose of a
developer friendly setup, and doesn't 'over deliver'. This leaves the way open
for 

To deploy this project on your own google project you need to:

1. Search and replace `ledger-2` with your own project
2. Search and replace `felixglasgow.com` in all yaml files under k8s.

It will take five minutes, and you can commit the results to your own fork. Done.

I very much like the idea of *seeding* configuration like this using jsonnet to
generate the initial configuration. [Databricks on jsonnet](https://databricks.com/blog/2017/06/26/declarative-infrastructure-jsonnet-templating-language.html)
has a lot of good insite here.

Going that road would mean a bootstraping step on fork/clone of the repo. This
approach has an [ancient and venerable](https://www.gnu.org/software/automake/faq/autotools-faq.html#What-does-_002e_002fbootstrap-or-_002e_002fautogen_002esh-do_003f)
precedent.


* [before you use kustomize](https://itnext.io/before-you-use-kustomize-eaa9529cdd19)
*
* [following this structure](https://kubectl.docs.kubernetes.io/pages/app_composition_and_deployment/structure_directories.html)
* [multi tier with composition](https://kubectl.docs.kubernetes.io/pages/app_composition_and_deployment/structure_multi_tier_apps.html)
* run-id and label conflicts sometimes require force or overriding lables to
    avoid the conflicts
  # https://github.com/GoogleContainerTools/skaffold/issues/3219
  queth
  skaffold.dev/run-id: static
  app.kubernetes.io/managed-by: skaffold

The first time I re-created a project from scratch with a new name, surpisingly
little of the kubernetes config needed to change. To accomodate a deployment
domain and a gcp project name change we need these kustomization's:

### Global

All image names need the projects docker image repository. Kustomization works
great here:

    # k8s/dev-example/kustomization.yaml
    images:
      - name: eu.gcr.io/quorumpreempt/shcurl
        newName: eu.gcr.io/ledger-2/shcurl
      - name: eu.gcr.io/quorumpreempt/adder
        newName: eu.gcr.io/ledger-2/adder
      - name: eu.gcr.io/quorumpreempt/quethraft-init
        newName: eu.gcr.io/ledger-2/quethraft-init
      - name: eu.gcr.io/quorumpreempt/nginx-web
        newName: eu.gcr.io/ledger-2/nginx-web

Replace ledger-2 with your <gcp_project_id>

Service Accounts in all namespaces. This is more cumbersome, but still not
dreadful. And the result is fairly clear. We need an RFC 6902 json patch for
each namespace that looks like this:

    - op: replace
      path: /metadata/annotations/iam.gke.io~1gcp-service-account
      value: kubeip-sa@ledger-2.iam.gserviceaccount.com

Note that ~1 is an escaped "/"

We also need a patch target specifying each patch in the kustomization.yaml

    patchesJson6902:
    # ledger sa's
    - target:
        group:
        version: v1
        kind: ServiceAccount
        namespace: queth
        name: quorum-genesis-sa
      path: quorum-genesis-sa-patch.yaml

Its at this point I started thinking seriously about jsonnet

We use the same approach for the ingress routes. Its a little more tricky
because we are patching a list item

The routes match for traefik

    apiVersion: traefik.containo.us/v1alpha1
    kind: IngressRoute
    metadata:
      name: ingressroutetls
    spec:
      entryPoints:
        - websecure
      routes:
        - match: Host(`queth.quorumpreempt.example.com`) && PathPrefix(`/adder`)

Patch

    - op: replace
      path: /spec/routes/0/match
      value: Host(`queth.ledger-2.felixglasgow.com`) && PathPrefix(`/adder`)

Domains will need same if doing wild card tls


### CaaS

adder deployment.yaml

init scripts which use a curl rune to collect secrtets directly

secret manager url in init container curl runes

    curl -sS "https://secretmanager.googleapis.com/v1/projects/<gcp_project_id>/secrets/qnode-0-wallet-key/versions/latest:access"

ETH_RPC vars for namespace prefixes - add if/when we add prefixes

    value: http://node-1.<namespacePrfix-queth|queth>.queth:8545

For both we can use [vars](https://kubectl.docs.kubernetes.io/pages/reference/kustomize.html#vars)
Which at least limits the changes to one place

But these are very contentions. Creating env vars and patching with overlays
appears the most reliable. patching via json patch notation is terrible as it
requires assumptions about list order.

### Ledger

nodeconf.yaml storage bucket name

    "bucket": "ledger-2-2c54a054-d234-d92c-e089-d7e0c61a23db",

### North

nginx route

    - match: Host(`queth.ledger-2.felixglasgow.com`) && PathPrefix(`/static`)

Traefik deployment.yaml

    - --certificatesresolvers.letsencrypt.acme.email=robinbryce@gmail.com

Things this projet uses vars for

vars are for getting post kustomize transformed values into env's and command
lines. They can not replace or templatize metadata.


To improve on the horrific env patch, we probably need overlays, and may need
to generate those. Merge patch for objects is easy to understand. For lists its
tricky and the documentation is not very clear on this *very* necessary usage

https://kubectl.docs.kubernetes.io/pages/app_management/field_merge_semantics.html

To replace a list item in a list that kubernets understands semantics for we
need to know the patch Key Name for the list items.jk


## Skaffold gotchas

* 
* default setup almost just works. traefik taints only permit one instance so the
  replacement is stuck pending until the old instance is manually deleted.
* kubectl deployment needs extra work (or can't handle) dependence on customer
  resource definitions or definition order dependencies
  [order of manifest respected since aug 2019](https://github.com/GoogleContainerTools/skaffold/pull/2729)
  Use the kustomise deployer
* --force allows skaffold to replace resource
* patch
*
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

## Cloud DNS, domain name and terraform

[Sort out a domain](https://cloud.google.com/dns/docs/tutorials/create-domain-tutorial) if
you don't already have one spare. If you do have one you will need to upate the
nameservers once we are done creating the managed zone.

Terraform fragments to create the manged zone and A record 

* https://www.terraform.io/docs/providers/google/d/dns_managed_zone.html
* https://www.terraform.io/docs/providers/google/r/dns_record_set.html

The terraform boils down to

    resource "google_dns_managed_zone" "preempt" {
      project = var.project
      name = "example-com-zone"
      dns_name = "example.com."
      description = "example dns zone"
    }

    resource "google_dns_record_set" "a" {
      name         = "ingress.preempt.${google_dns_managed_zone.preempt.dns_name}"
      managed_zone = google_dns_managed_zone.preempt.name
      type         = "A"
      ttl          = 300

      rrdatas = [google_compute_address.static-ingress.address]
    }

    resource "google_dns_record_set" "cname" {
      name         = "queth.preempt.${google_dns_managed_zone.preempt.dns_name}"
      managed_zone = google_dns_managed_zone.preempt.name
      type         = "CNAME"
      ttl          = 300

      rrdatas = ["queth.preempt.${google_dns_managed_zone.preempt.dns_name}"]
    }



## cert-manager

[Google Cloud DNS & Cert-Manager][https://cert-manager.io/docs/configuration/acme/dns01/google/]

[HTTPs with Cert-Manager on GKE](https://medium.com/google-cloud/https-with-cert-manager-on-gke-49a70985d99b)

cert-manager using regular manifests with skaffold. cert-managers docs are
[here](https://cert-manager.io/docs/installation/kubernetes/)

[cert-manager & kustomize](https://blog.jetstack.io/blog/kustomize-cert-manager/)

Add the following skaffold profile ( < k8s 1.15)

  - name: certmanager
    deploy:
      kubectl:
        flags:
          disableValidation: true
        manifests:
        - https://github.com/jetstack/cert-manager/releases/download/v0.15.1/cert-manager-legacy.yaml

Use the non legacy variant if the cluster is on >= 1.15 as described [here](https://cert-manager.io/docs/installation/kubernetes/)

Check the deployment using the  test-resources.yaml described on that page. Then run

    kubectl describe certificate -n cert-manager-test

We want to see an event message like this

    Normal  Issued        37s   cert-manager  Certificate issued successfully

Familiarise with Google Cloud DNS [quickstart](https://cloud.google.com/dns/docs/quickstart)


    * [cert-manager Google resolver](https://cert-manager.io/docs/configuration/acme/dns01/google/)
    * [old sa/key method](https://cloud.google.com/kubernetes-engine/docs/tutorials/authenticating-to-cloud-platform)
    has to be used afaict

To use cert-manager with workload identity, create an [additional api
token](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/)
with a stable name.

    apiVersion: v1
    kind: Secret
    metadata:
      name: dns01solver-sa-token
      namespace: cert-manager
      annotations:
        kubernetes.io/service-account.name: dns01solver-sa
    type: kubernetes.io/service-account-token

Nope: this does not work, falling back to explicit key method. managing via
task file for now

    gcloud iam service-accounts keys create \
      key.json --iam-account dns01solver-sa@quorumpreempt.iam.gserviceaccount.com
    gcloud projects add-iam-policy-binding quorumpreempt \
      --member serviceAccount:dns01solver-sa@quorumpreempt.iam.gserviceaccount.com \
      --role roles/dns.admin

    kubectl -n cert-manager delete secret dns01solver-sa-key || true
    kubectl -n cert-manager create secret generic dns01solver-sa-key \
      --from-file key.json

But traeffic can do dns01 challenge resolution on its own and uses LEGO so
maybe we can use the workload identity directly ?

## old create secrets
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


