# -----------------------------------------------------------------------------
# Terraform Backend Configuration (PARTIAL)
# -----------------------------------------------------------------------------
# storage_account_name and key are intentionally omitted so the value isn't
# duplicated across this file and CI workflows on every subscription switch.
# CI passes both via -backend-config flags (storage account from the
# TFSTATE_STORAGE_ACCOUNT GH repo variable; key per environment).
#
# Local init:
#   terraform init \
#     -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
#     -backend-config="key=ghrunners/<env>/terraform.tfstate"
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {
    resource_group_name = "rg-terraform-state"
    container_name      = "tfstate"
    use_azuread_auth    = true
    # storage_account_name + key supplied via -backend-config at init time
  }
}
