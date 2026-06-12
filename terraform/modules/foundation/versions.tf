# Declare non-default provider sources used in this module.
# Required because azapi is not under the default hashicorp/ namespace.
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}
