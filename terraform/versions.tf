# -----------------------------------------------------------------------------
# Terraform Version and Provider Constraints
# -----------------------------------------------------------------------------
# Provider versions pinned to exact versions from .terraform.lock.hcl
# This ensures reproducible builds and prevents unexpected breaking changes
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.117.1"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}
