# -----------------------------------------------------------------------------
# Terraform Backend Configuration - Development (PARTIAL)
# -----------------------------------------------------------------------------
# Local init:
#   terraform init \
#     -backend-config=environments/dev/backend.tf \
#     -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT"
#
# CI passes storage_account_name via the TFSTATE_STORAGE_ACCOUNT repo variable.
# This file contributes the per-env state key. Keeping the two values in
# separate sources prevents the storage account from getting hardcoded across
# multiple files (the cause of the 2026-05-07 sub-switch search-and-replace).
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {
    resource_group_name = "rg-terraform-state"
    container_name      = "tfstate"
    key                 = "ghrunners/dev/terraform.tfstate"
    use_azuread_auth    = true
    # storage_account_name supplied via -backend-config at init time
  }
}
