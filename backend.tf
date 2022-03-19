terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.1.0"
    }
  }
  required_version = ">= 1.1.6"

  #  cloud {
  #    organization = "opslab-test"
  #
  #    workspaces {
  #      name = "infra-eks"
  #    }
  #  }
}
