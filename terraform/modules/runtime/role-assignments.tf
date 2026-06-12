# -----------------------------------------------------------------------------
# Role Assignments - Runtime Module
# Creates 19 RBAC role assignments for least privilege access
# Uses deterministic names (UUIDs) to prevent "RoleAssignmentExists" errors
# -----------------------------------------------------------------------------

# Built-in role definition IDs
locals {
  role_definitions = {
    contributor                    = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    reader                         = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    virtual_machine_contributor    = "9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
    network_contributor            = "4d97b98b-1d4f-4787-a291-c67834d212e7"
    storage_blob_data_contributor  = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    storage_table_data_contributor = "0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3"
    storage_table_data_reader      = "76199698-9eea-4c19-bc75-cec21354c6b4"
    storage_queue_data_contributor = "974c5e8b-45b9-4653-ba55-5f855dd0fb88"
  }

  # Generate deterministic role assignment names based on principal, role, and scope
  # This prevents "RoleAssignmentExists" errors when re-running deployments
  role_assignment_names = {
    vmss_network_contributor    = uuidv5("url", "${var.vmss_identity_principal_id}-NetworkContributor-${var.resource_group_id}")
    vmss_reader                 = uuidv5("url", "${var.vmss_identity_principal_id}-Reader-${var.resource_group_id}")
    vmss_storage_blob_scaleout  = uuidv5("url", "${var.vmss_identity_principal_id}-StorageBlobDataContributor-${var.storage_scaleout_id}")
    vmss_storage_table_scaleout = uuidv5("url", "${var.vmss_identity_principal_id}-StorageTableDataContributor-${var.storage_scaleout_id}")

    scaleout_vm_contributor      = uuidv5("url", "${var.scaleout_identity_principal_id}-VirtualMachineContributor-${var.resource_group_id}")
    scaleout_reader              = uuidv5("url", "${var.scaleout_identity_principal_id}-Reader-${var.resource_group_id}")
    scaleout_storage_blob        = uuidv5("url", "${var.scaleout_identity_principal_id}-StorageBlobDataContributor-${var.storage_scaleout_id}")
    scaleout_storage_queue       = uuidv5("url", "${var.scaleout_identity_principal_id}-StorageQueueDataContributor-${var.storage_scaleout_id}")
    scaleout_storage_table       = uuidv5("url", "${var.scaleout_identity_principal_id}-StorageTableDataContributor-${var.storage_scaleout_id}")
    scaleout_network_contributor = uuidv5("url", "${var.scaleout_identity_principal_id}-NetworkContributor-${var.resource_group_id}")
    scaleout_contributor         = uuidv5("url", "${var.scaleout_identity_principal_id}-Contributor-${var.resource_group_id}")
    scaleout_keyvault_secrets    = uuidv5("url", "${var.scaleout_identity_principal_id}-KeyVaultSecretsUser-${var.key_vault_id}")

    scalein_vm_contributor             = uuidv5("url", "${var.scalein_identity_principal_id}-VirtualMachineContributor-${var.resource_group_id}")
    scalein_reader                     = uuidv5("url", "${var.scalein_identity_principal_id}-Reader-${var.resource_group_id}")
    scalein_storage_blob               = uuidv5("url", "${var.scalein_identity_principal_id}-StorageBlobDataContributor-${var.storage_scalein_id}")
    scalein_storage_queue              = uuidv5("url", "${var.scalein_identity_principal_id}-StorageQueueDataContributor-${var.storage_scalein_id}")
    scalein_storage_table              = uuidv5("url", "${var.scalein_identity_principal_id}-StorageTableDataContributor-${var.storage_scalein_id}")
    scalein_scaleout_table_contributor = uuidv5("url", "${var.scalein_identity_principal_id}-StorageTableDataContributor-${var.storage_scaleout_id}")
    scalein_contributor                = uuidv5("url", "${var.scalein_identity_principal_id}-Contributor-${var.resource_group_id}")
  }
}

# -----------------------------------------------------------------------------
# VMSS Identity Role Assignments (5 roles)
# -----------------------------------------------------------------------------

# VMSS: Network Contributor on Resource Group
resource "azurerm_role_assignment" "vmss_network_contributor" {
  count = var.create_vmss_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.vmss_network_contributor
  scope                = var.resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = var.vmss_identity_principal_id
}

# VMSS: Reader on Resource Group
resource "azurerm_role_assignment" "vmss_reader" {
  count = var.create_vmss_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.vmss_reader
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = var.vmss_identity_principal_id
}

# VMSS: Storage Blob Data Contributor on ScaleOut Storage
resource "azurerm_role_assignment" "vmss_storage_blob_scaleout" {
  count = var.create_vmss_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.vmss_storage_blob_scaleout
  scope                = var.storage_scaleout_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.vmss_identity_principal_id
}

# VMSS: Storage Table Data Contributor on ScaleOut Storage
resource "azurerm_role_assignment" "vmss_storage_table_scaleout" {
  count = var.create_vmss_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.vmss_storage_table_scaleout
  scope                = var.storage_scaleout_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.vmss_identity_principal_id
}

# VMSS: Key Vault Secrets User - REMOVED
# GitHub PAT retrieval is now handled in the pre-baked VM image, not at runtime

# -----------------------------------------------------------------------------
# ScaleOut Function Identity Role Assignments (7 roles)
# -----------------------------------------------------------------------------

# ScaleOut: Virtual Machine Contributor on Resource Group
resource "azurerm_role_assignment" "scaleout_vm_contributor" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_vm_contributor
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = var.scaleout_identity_principal_id
}

# ScaleOut: Reader on Resource Group
resource "azurerm_role_assignment" "scaleout_reader" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_reader
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = var.scaleout_identity_principal_id
}

# ScaleOut: Storage Blob Data Contributor on ScaleOut Storage
resource "azurerm_role_assignment" "scaleout_storage_blob" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_storage_blob
  scope                = var.storage_scaleout_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.scaleout_identity_principal_id
}

# ScaleOut: Storage Queue Data Contributor on ScaleOut Storage
resource "azurerm_role_assignment" "scaleout_storage_queue" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_storage_queue
  scope                = var.storage_scaleout_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.scaleout_identity_principal_id
}

# ScaleOut: Storage Table Data Contributor on ScaleOut Storage
resource "azurerm_role_assignment" "scaleout_storage_table" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_storage_table
  scope                = var.storage_scaleout_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.scaleout_identity_principal_id
}

# ScaleOut: Network Contributor on Resource Group
resource "azurerm_role_assignment" "scaleout_network_contributor" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_network_contributor
  scope                = var.resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = var.scaleout_identity_principal_id
}

# ScaleOut: Contributor on Resource Group (for VMSS scaling)
resource "azurerm_role_assignment" "scaleout_contributor" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_contributor
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = var.scaleout_identity_principal_id
}

# -----------------------------------------------------------------------------
# ScaleIn Function Identity Role Assignments (7 roles)
# -----------------------------------------------------------------------------

# ScaleIn: Virtual Machine Contributor on Resource Group
resource "azurerm_role_assignment" "scalein_vm_contributor" {
  count = var.create_scalein_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_vm_contributor
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = var.scalein_identity_principal_id
}

# ScaleIn: Reader on Resource Group
resource "azurerm_role_assignment" "scalein_reader" {
  count = var.create_scalein_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_reader
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = var.scalein_identity_principal_id
}

# ScaleIn: Storage Blob Data Contributor on ScaleIn Storage
# Uses separate flag — scope is storage_scalein_id, never a duplicate of ScaleOut's storage_scaleout_id
resource "azurerm_role_assignment" "scalein_storage_blob" {
  count = var.create_scalein_storage_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_storage_blob
  scope                = var.storage_scalein_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.scalein_identity_principal_id
}

# ScaleIn: Storage Queue Data Contributor on ScaleIn Storage
resource "azurerm_role_assignment" "scalein_storage_queue" {
  count = var.create_scalein_storage_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_storage_queue
  scope                = var.storage_scalein_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.scalein_identity_principal_id
}

# ScaleIn: Storage Table Data Contributor on ScaleIn Storage
resource "azurerm_role_assignment" "scalein_storage_table" {
  count = var.create_scalein_storage_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_storage_table
  scope                = var.storage_scalein_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.scalein_identity_principal_id
}

# ScaleIn: Storage Table Data Contributor on ScaleOut Storage
# Required by: ProcVmssScaleInQueue — writes VmssScaleTracking (marks VM available)
#              ProcVmssDeleteAvailableVMs — deletes rows from VmssScaleAvailable
# This is NEW for the queue-based webhook scaling architecture.
resource "azurerm_role_assignment" "scalein_scaleout_table_contributor" {
  count = var.create_scalein_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_scaleout_table_contributor
  scope                = var.storage_scaleout_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.scalein_identity_principal_id
}

# ScaleIn: Contributor on Resource Group (for VMSS scaling)
resource "azurerm_role_assignment" "scalein_contributor" {
  count = var.create_scalein_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scalein_contributor
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = var.scalein_identity_principal_id
}

# -----------------------------------------------------------------------------
# Key Vault Role Assignments
# -----------------------------------------------------------------------------
# Grant Function Apps access to read GitHub secrets from Key Vault
# Using "Key Vault Secrets User" role for least privilege (read-only access)
# -----------------------------------------------------------------------------

# ScaleOut: Key Vault Secrets User (for reading GitHub credentials)
resource "azurerm_role_assignment" "scaleout_keyvault_secrets" {
  count = var.create_scaleout_role_assignments ? 1 : 0

  name                 = local.role_assignment_names.scaleout_keyvault_secrets
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.scaleout_identity_principal_id
}

# -----------------------------------------------------------------------------
# Unified Deploy UAMI: Website Contributor scoped per function app
# -----------------------------------------------------------------------------
# One UAMI (id-ghrunners-deploy) with multiple FICs — each consumer repo's GH
# Actions workflow federates against the same principal but is granted access
# only to its own function app. Per-app role scope preserves blast-radius
# isolation while collapsing the previous 2 separate deploy UAMIs into one.
#
# count predicate uses only static flags — principal_id is created in this
# same plan and would force plan-time uncertainty if used in count.
#
# `name` is intentionally omitted so TF adopts the GUID Azure mints (and so
# imports don't churn).
resource "azurerm_role_assignment" "deploy_scalein_website_contributor" {
  count = var.create_unified_deploy_role_assignments && var.deploy_functions ? 1 : 0

  scope                = azurerm_windows_function_app.scalein[0].id
  role_definition_name = "Website Contributor"
  principal_id         = var.deploy_identity_principal_id
}

resource "azurerm_role_assignment" "deploy_scaleout_website_contributor" {
  count = var.create_unified_deploy_role_assignments && var.deploy_functions ? 1 : 0

  scope                = azurerm_windows_function_app.scaleout[0].id
  role_definition_name = "Website Contributor"
  principal_id         = var.deploy_identity_principal_id
}

resource "azurerm_role_assignment" "deploy_scaleout_webhook_website_contributor" {
  count = var.create_unified_deploy_role_assignments && var.deploy_functions && var.deploy_scaleout_webhook_app ? 1 : 0

  scope                = azurerm_windows_function_app.scaleout_webhook[0].id
  role_definition_name = "Website Contributor"
  principal_id         = var.deploy_identity_principal_id
}
