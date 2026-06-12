# -----------------------------------------------------------------------------
# Provider Configuration - GitHub VMSS Runners Infrastructure
# -----------------------------------------------------------------------------
# Provider features configuration
# Note: prevent_deletion_if_contains_resources is set per environment via tfvars
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = var.prevent_resource_group_deletion
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }

  # Use Azure AD authentication for storage data plane operations
  # This allows storage accounts to have shared_access_key_enabled = false
  storage_use_azuread = true
}

provider "azapi" {}

provider "random" {}

# GitHub provider — used to push AZURE_CLIENT_ID env secrets to consumer
# function-app repos via Option A in modules/foundation/deploy-identities.tf.
# Owner is fixed to eh-ciellos because that's where ScaleIn/ScaleOut function
# repos live; the PAT is fine-grained and scoped to those two repos only.
# When github_secrets_pat is empty, no env_secret resources are created so
# the provider config is harmless (provider is loaded but unused).
provider "github" {
  owner = "eh-ciellos"
  token = var.github_secrets_pat
}

# Second GitHub provider — used to push AZURE_SUBSCRIPTION_ID repo-level
# secret to gitspacecadet/vm-runner-image (the Packer image-build repo).
# Distinct alias because:
# 1. vm-runner-image lives in a different GH org (gitspacecadet vs eh-ciellos),
#    and least-privilege PATs shouldn't span both
# 2. vm-runner-image's BuildALGoRunnerImage.yaml workflow doesn't use GH
#    Environments — it reads repo-level secrets — so we need github_actions_secret
#    not github_actions_environment_secret
# 3. Keeps the two PATs' blast radii separate: eh-ciellos PAT can't touch
#    gitspacecadet repos and vice versa
#
# When github_image_builder_pat is empty, the provider is unused and the
# secret resource skips creation (count predicate gated). vm-runner-image
# retains whatever AZURE_SUBSCRIPTION_ID value was last manually set.
provider "github" {
  alias = "image_builder_scope"
  owner = "gitspacecadet"
  token = var.github_image_builder_pat
}
