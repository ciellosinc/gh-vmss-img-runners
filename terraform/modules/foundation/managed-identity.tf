# -----------------------------------------------------------------------------
# Managed Identities - Foundation Module
# Creates 0-3 user-assigned managed identities based on environment strategy
# -----------------------------------------------------------------------------

# VMSS Managed Identity
resource "azurerm_user_assigned_identity" "vmss" {
  count = var.identity_strategy.create_vmss_identity ? 1 : 0

  name                = var.resource_names.identity_vmss
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ScaleOut Function Managed Identity
resource "azurerm_user_assigned_identity" "scaleout" {
  count = var.identity_strategy.create_scaleout_identity ? 1 : 0

  name                = var.resource_names.identity_scaleout
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ScaleIn Function Managed Identity
resource "azurerm_user_assigned_identity" "scalein" {
  count = var.identity_strategy.create_scalein_identity ? 1 : 0

  name                = var.resource_names.identity_scalein
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Shared Managed Identity (for test environment)
resource "azurerm_user_assigned_identity" "shared" {
  count = var.identity_strategy.use_shared_identity ? 1 : 0

  name                = var.resource_names.identity_shared
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Image Builder Managed Identity (separate from id-ghrunners-deploy for
# blast-radius isolation — Packer needs sub-wide Contributor; function-app
# deploys only need scoped roles per app). OIDC-federated via FIC in
# deploy-identities.tf with subject targeting GH environment image-build
# on gitspacecadet/vm-runner-image. Replaces the legacy gh-runner-image-
# builder SP + client-secret auth. See FromVmImageAgent/21-extend-oidc-
# pattern-to-image-builder-2026-05-22.md for the migration rationale.
resource "azurerm_user_assigned_identity" "image_builder" {
  count = var.create_image_builder_identity ? 1 : 0

  name                = "id-ghrunners-image-builder"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Local values for identity resolution
# -----------------------------------------------------------------------------

locals {
  # Resolve VMSS identity (shared or dedicated)
  vmss_identity_id = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].id : null
    ) : (
    length(azurerm_user_assigned_identity.vmss) > 0 ? azurerm_user_assigned_identity.vmss[0].id : null
  )

  vmss_identity_principal_id = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].principal_id : null
    ) : (
    length(azurerm_user_assigned_identity.vmss) > 0 ? azurerm_user_assigned_identity.vmss[0].principal_id : null
  )

  # Resolve ScaleOut identity (shared or dedicated)
  scaleout_identity_id = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].id : null
    ) : (
    length(azurerm_user_assigned_identity.scaleout) > 0 ? azurerm_user_assigned_identity.scaleout[0].id : null
  )

  scaleout_identity_principal_id = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].principal_id : null
    ) : (
    length(azurerm_user_assigned_identity.scaleout) > 0 ? azurerm_user_assigned_identity.scaleout[0].principal_id : null
  )

  # Resolve ScaleIn identity (shared or dedicated)
  scalein_identity_id = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].id : null
    ) : (
    length(azurerm_user_assigned_identity.scalein) > 0 ? azurerm_user_assigned_identity.scalein[0].id : null
  )

  scalein_identity_principal_id = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].principal_id : null
    ) : (
    length(azurerm_user_assigned_identity.scalein) > 0 ? azurerm_user_assigned_identity.scalein[0].principal_id : null
  )
}
