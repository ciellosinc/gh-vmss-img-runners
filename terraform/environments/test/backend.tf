# -----------------------------------------------------------------------------
# Terraform Backend Configuration - Test
# -----------------------------------------------------------------------------
# Remote state storage with Azure AD authentication (no storage keys)
# State locking enabled via Azure Blob lease mechanism
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {
    resource_group_name = "rg-terraform-state"
    container_name      = "tfstate"
    key                 = "ghrunners/test/terraform.tfstate"
    use_azuread_auth    = true
    # storage_account_name supplied via -backend-config (TFSTATE_STORAGE_ACCOUNT
    # repo variable in CI; export locally before running terraform init)
  }
}
