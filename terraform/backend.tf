# -----------------------------------------------------------------------------
# Terraform Backend Configuration (FULLY PARAMETERIZED)
# -----------------------------------------------------------------------------
# All backend values are passed via -backend-config flags so operators can pick
# their own naming convention without editing this file. The CI workflows read
# from GitHub repo variables seeded by Installation/Set-GitHubSecrets.ps1:
#
#   resource_group_name  ← TFSTATE_RESOURCE_GROUP_NAME    (default rg-terraform-state)
#   storage_account_name ← TFSTATE_STORAGE_ACCOUNT        (no default, mandatory)
#   container_name       ← TFSTATE_CONTAINER_NAME         (default tfstate)
#   key                  ← per-env, ghrunners/<env>/terraform.tfstate
#
# Local init example:
#   terraform init \
#     -backend-config="resource_group_name=$TFSTATE_RESOURCE_GROUP_NAME" \
#     -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
#     -backend-config="container_name=$TFSTATE_CONTAINER_NAME" \
#     -backend-config="key=ghrunners/<env>/terraform.tfstate"
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {
    use_azuread_auth = true
    # All other backend values supplied via -backend-config at init time
  }
}
