# Running quorum on preemptible GCP instances aka 'consortia ledger on the cheap'
Stuff that probably isn't worth writing up but which may be a handy reference

* 2nd envoy to do grpc transcoding https://www.envoyproxy.io/docs/envoy/v1.9.0/configuration/http_filters/grpc_json_transcoder_filter

## Switching it all over from kubectl to kustomize

* [before you use kustomize](https://itnext.io/before-you-use-kustomize-eaa9529cdd19)
*
* [following this structure](https://kubectl.docs.kubernetes.io/pages/app_composition_and_deployment/structure_directories.html)
* [multi tier with composition](https://kubectl.docs.kubernetes.io/pages/app_composition_and_deployment/structure_multi_tier_apps.html)

## Skaffold gotchas

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

