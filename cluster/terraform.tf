terraform {
  required_version = "~> 0.12"
  backend "remote" {
    organization = "robinbryce"
    workspaces {
      name = "consortia-quorum-preempt"
    }
  }
}
