# -----------------------------------------------------------------------------
# Storage Accounts - Foundation Module
# Creates storage accounts for ScaleOut and ScaleIn function apps
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ScaleOut Storage Account
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "scaleout" {
  name                     = var.resource_names.storage_scaleout
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = var.storage_config.account_tier
  account_replication_type = var.storage_config.account_replication_type
  account_kind             = var.storage_config.account_kind
  access_tier              = var.storage_config.access_tier
  min_tls_version          = var.storage_config.min_tls_version

  # Disable shared key access (use Managed Identity only)
  shared_access_key_enabled = false

  # Enable blob public access disabled for security
  allow_nested_items_to_be_public = false

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Scale-Out Storage: Queues and Tables (Queue-Based Webhook Scaling)
# -----------------------------------------------------------------------------
# Queues decouple webhook reception from VMSS API calls (webhooks return fast,
# queue processors handle retries). Tables track the VM availability pool and
# active job assignments.
# -----------------------------------------------------------------------------

# Queue: receives scale-out requests from GhWebHookScaleOut
resource "azurerm_storage_queue" "scaleout_requests" {
  name                 = var.scaling_queue_names.scaleout
  storage_account_name = azurerm_storage_account.scaleout.name
}

# Table: pool of warm/idle VM instances available to absorb the next job
# Uses azapi_resource (ARM control plane) instead of azurerm_storage_table because
# azurerm v3 calls SetTableACL via key-based auth, blocked by shared_access_key_enabled=false.
resource "azapi_resource" "vmss_scale_available" {
  type      = "Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01"
  name      = var.scaling_table_names.available
  parent_id = "${azurerm_storage_account.scaleout.id}/tableServices/default"
  body      = {}

  ignore_missing_property = true
}

# Table: maps workflow_run_id → VmInstanceId for active job tracking
resource "azapi_resource" "vmss_scale_tracking" {
  type      = "Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01"
  name      = var.scaling_table_names.tracking
  parent_id = "${azurerm_storage_account.scaleout.id}/tableServices/default"
  body      = {}

  ignore_missing_property = true
}

# Table: pending self-attribution rows (Arch B Phase 4B).
# ScaleOut writes one row per scale-up call (PartitionKey=vmssName, RowKey=<utc-iso>_<runId>),
# Status=pending. Each new VM, at boot, claims the oldest pending row via ETag-protected
# MERGE in Initialize-GhRunner.ps1. Eliminates the "highest InstanceId" sampling race that
# leaked orphan VMs under concurrent scale operations (Bug 2 in ScaleOut).
# Schema is informational (Tables are schemaless); see ScaleOut + vm-image hand-offs:
#   .claude/Docs/FromScaleoOutAgent/03-arch-b-schema-delta-from-vmimage-findings-2026-04-25.md
#   .claude/Docs/FromVmImageAgent/RE-02-final-claim-function-with-tracking-merge-2026-04-25.md
resource "azapi_resource" "vmss_scale_pending" {
  type      = "Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01"
  name      = var.scaling_table_names.pending
  parent_id = "${azurerm_storage_account.scaleout.id}/tableServices/default"
  body      = {}

  ignore_missing_property = true
}

# Table: reconciliation drift tracking (Arch B Phase 5).
# ScaleIn's ProcVmssReconciliation timer writes drift catalog entries here when
# the GitHub runners API state diverges from VmssScaleAvailable/VmssScaleTracking.
# Read-only by default (RECONCILE_AUTOFIX=false); flip to true after observation
# window to enable auto-cleanup. Schema is informational (Tables are schemaless).
# See .claude/Docs/Tracking/2026-04-26-phase5-activation-lockstep.md and
# .claude/Docs/FromScaleInAgent/05-pr7-ack-and-phase5-activation-note-2026-04-26.md.
resource "azapi_resource" "vmss_reconcile_tracking" {
  type      = "Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01"
  name      = var.scaling_table_names.reconcile_tracking
  parent_id = "${azurerm_storage_account.scaleout.id}/tableServices/default"
  body      = {}

  ignore_missing_property = true
}

# -----------------------------------------------------------------------------
# VMSS Runner Initialization Script (Blob Storage)
# -----------------------------------------------------------------------------
# The runner registration script is uploaded to a blob container in ScaleOut
# storage. VMSS instances download it at boot via CustomScriptExtension using
# managed identity auth (no SAS, no key — shared_access_key_enabled=false).
# -----------------------------------------------------------------------------

# Grant the Terraform deployer (OIDC SP) blob data-plane access on ScaleOut storage.
# Required because azurerm_storage_blob uses the data-plane API, which needs
# Storage Blob Data Contributor — Contributor (ARM control plane) is not enough.
resource "azurerm_role_assignment" "deployer_blob_contributor" {
  scope                = azurerm_storage_account.scaleout.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "vmss_scripts" {
  name                  = "vmss-scripts"
  storage_account_name  = azurerm_storage_account.scaleout.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "runner_init_script" {
  name                   = "Initialize-GhRunner.ps1"
  storage_account_name   = azurerm_storage_account.scaleout.name
  storage_container_name = azurerm_storage_container.vmss_scripts.name
  type                   = "Block"
  # Source moved under terraform/scripts/ so edits trigger terraform-ci.yml's
  # paths filter (terraform/**). Old location (Scripts/) kept for one cycle in
  # case of rollback; will be removed in a follow-up after this apply lands.
  source      = "${path.root}/scripts/Initialize-GhRunner.ps1"
  content_md5 = filemd5("${path.root}/scripts/Initialize-GhRunner.ps1")

  depends_on = [azurerm_role_assignment.deployer_blob_contributor]
}

# -----------------------------------------------------------------------------
# Scale-In Storage: Queue (Queue-Based Webhook Scaling)
# -----------------------------------------------------------------------------

# Queue: receives scale-in requests from GhWebHookScaleIn
resource "azurerm_storage_queue" "scalein_requests" {
  name                 = var.scaling_queue_names.scalein
  storage_account_name = azurerm_storage_account.scalein.name
}

# -----------------------------------------------------------------------------
# ScaleIn Storage Account
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "scalein" {
  name                     = var.resource_names.storage_scalein
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = var.storage_config.account_tier
  account_replication_type = var.storage_config.account_replication_type
  account_kind             = var.storage_config.account_kind
  access_tier              = var.storage_config.access_tier
  min_tls_version          = var.storage_config.min_tls_version

  # Disable shared key access (use Managed Identity only)
  shared_access_key_enabled = false

  # Enable blob public access disabled for security
  allow_nested_items_to_be_public = false

  tags = var.tags
}
