terraform {
  required_version = "~> 0.12"
  required_providers {
    google-beta = ">= 3.8"
  }
  backend "remote" {
    organization = "robinbryce"
    workspaces {
      name = "quorumpreempt-284308-cluster"
    }
  }
}
