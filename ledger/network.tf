resource "google_dns_managed_zone" "primary" {
  project = local.gcp_project_id
  name = "primary-dns"
  dns_name = "${var.ingress_domain}."
  description = "dns zone"
}

resource "google_dns_record_set" "a" {
  project = local.gcp_project_id
  name = "${local.gcp_project_id}.${google_dns_managed_zone.primary.dns_name}"
  managed_zone = google_dns_managed_zone.primary.name
  type = "A"
  ttl = 300

  rrdatas = [local.static_ingress] # remote state from cluster
}

resource "google_dns_record_set" "cname" {
  project = local.gcp_project_id
  name = "queth.${local.gcp_project_id}.${google_dns_managed_zone.primary.dns_name}"
  managed_zone = google_dns_managed_zone.primary.name
  type = "CNAME"
  ttl = 300

  rrdatas = ["${local.gcp_project_id}.${google_dns_managed_zone.primary.dns_name}"]
}
