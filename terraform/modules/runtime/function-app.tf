# -----------------------------------------------------------------------------
# Function Apps - Runtime Module
# Creates ScaleOut and ScaleIn function apps with their service plans
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ScaleOut Function App
# -----------------------------------------------------------------------------

# App Service Plan for ScaleOut
resource "azurerm_service_plan" "scaleout" {
  count = var.deploy_functions ? 1 : 0

  name                = var.resource_names.asp_scaleout
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = var.function_config.os_type
  sku_name            = var.function_config.sku_name

  tags = var.tags
}

# ScaleOut Function App
resource "azurerm_windows_function_app" "scaleout" {
  count = var.deploy_functions ? 1 : 0

  name                = var.resource_names.func_scaleout
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.scaleout[0].id

  storage_account_name          = var.storage_scaleout_name
  storage_uses_managed_identity = true

  # Direct all @Microsoft.KeyVault(...) reference resolution to the user-assigned MI
  # Required when no system-assigned MI exists — without this, Azure tries SA-MI and fails with MSINotEnabled
  key_vault_reference_identity_id = var.scaleout_identity_id

  # User-assigned managed identity
  dynamic "identity" {
    for_each = var.scaleout_identity_id != null ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.scaleout_identity_id]
    }
  }

  # System-assigned identity fallback
  dynamic "identity" {
    for_each = var.scaleout_identity_id == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  site_config {
    application_stack {
      powershell_core_version = var.function_config.powershell_version
    }

    application_insights_connection_string = azurerm_application_insights.scaleout.connection_string
    application_insights_key               = azurerm_application_insights.scaleout.instrumentation_key
  }

  # Optional WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT.
  #
  # ⚠️  EMPIRICAL FINDING (2026-04-26 burst test): this setting does NOT
  # serialize queue triggers on Y1 Consumption. Three messages processed
  # within 4 seconds of each other while the setting was live — the
  # in-instance concurrency for queue triggers is governed by host.json
  # (batchSize/newBatchThreshold), not by this app-wide worker cap.
  # See .claude/Docs/Tracking/2026-04-26-scaleout-worker-cap-non-functional.md.
  #
  # Originally set to "1" as defense against Bug 2 (VMSS-InstanceId sampling
  # race in ProcVmssScaleQueue). Phase 4B replaced that defense with
  # self-attribution (VMs claim their own pending row at boot). The cap was
  # never actually doing what it was thought to do; null is the correct
  # value going forward. Variable retained for test/prod opt-in.
  app_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME"    = "powershell"
      "FUNCTIONS_EXTENSION_VERSION" = var.function_config.runtime_version

      # MI-based host storage — required when shared_access_key_enabled=false on the storage account.
      # Without all three, the queue trigger never polls (host falls back to key-based connection string).
      "AzureWebJobsStorage__accountName" = var.storage_scaleout_name
      "AzureWebJobsStorage__credential"  = "managedidentity"
      "AzureWebJobsStorage__clientId"    = var.managed_identity_client_id

      # Deployment mode — "1" = run from zip package in host storage. Safe even with
      # shared_access_key_enabled=false because the zip read uses the same MI auth
      # path configured above (AzureWebJobsStorage__credential=managedidentity).
      # Kept in TF to prevent drift removal: azurerm's app_settings is authoritative.
      "WEBSITE_RUN_FROM_PACKAGE" = "1"

      # GitHub authentication
      "GITHUB_AUTH_STRATEGY"   = var.github_auth_strategy
      "GITHUB_APP_ID"          = var.github_app_id
      "GITHUB_INSTALLATION_ID" = var.github_installation_id
      "GITHUB_ORGANIZATION"    = var.github_organization

      # KV references — ;clientId= required when no system-assigned MI exists (defence-in-depth with key_vault_reference_identity_id)
      "GITHUB_PRIVATE_KEY" = var.github_private_key_secret_uri != null ? (
        var.managed_identity_client_id != null
        ? "@Microsoft.KeyVault(SecretUri=${var.github_private_key_secret_uri};clientId=${var.managed_identity_client_id})"
        : "@Microsoft.KeyVault(SecretUri=${var.github_private_key_secret_uri})"
      ) : ""
      "GITHUB_PAT" = var.github_pat_secret_uri != null ? (
        var.managed_identity_client_id != null
        ? "@Microsoft.KeyVault(SecretUri=${var.github_pat_secret_uri};clientId=${var.managed_identity_client_id})"
        : "@Microsoft.KeyVault(SecretUri=${var.github_pat_secret_uri})"
      ) : ""

      # VMSS reference
      "VMSS_NAME"           = var.resource_names.vmss
      "VMSS_RESOURCE_GROUP" = var.resource_group_name

      # Queue/table names used by GhWebHookScaleOut + ProcVmssScaleQueue
      "STORAGE_ACCOUNT_NAME" = var.storage_scaleout_name
      "QUEUE_SCALEOUT_NAME"  = var.scaleout_queue_name
      "TABLE_AVAILABLE_NAME" = var.table_available_name
      "TABLE_TRACKING_NAME"  = var.table_tracking_name
    },
    var.scaleout_max_scale_out_workers != null ? {
      "WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT" = tostring(var.scaleout_max_scale_out_workers)
    } : {}
  )

  tags = var.tags

  # Dependencies - ensure RBAC is ready before function app starts
  depends_on = [
    azurerm_role_assignment.scaleout_vm_contributor,
    azurerm_role_assignment.scaleout_storage_blob,
    azurerm_role_assignment.scaleout_storage_queue,
    azurerm_role_assignment.scaleout_storage_table,
    azurerm_role_assignment.scaleout_keyvault_secrets
  ]
}

# -----------------------------------------------------------------------------
# ScaleIn Function App
# -----------------------------------------------------------------------------

# App Service Plan for ScaleIn
resource "azurerm_service_plan" "scalein" {
  count = var.deploy_functions ? 1 : 0

  name                = var.resource_names.asp_scalein
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = var.function_config.os_type
  sku_name            = var.function_config.sku_name

  tags = var.tags
}

# ScaleIn Function App
resource "azurerm_windows_function_app" "scalein" {
  count = var.deploy_functions ? 1 : 0

  name                = var.resource_names.func_scalein
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.scalein[0].id

  storage_account_name          = var.storage_scalein_name
  storage_uses_managed_identity = true

  # Direct all @Microsoft.KeyVault(...) reference resolution to the user-assigned MI
  key_vault_reference_identity_id = var.scalein_identity_id

  # User-assigned managed identity
  dynamic "identity" {
    for_each = var.scalein_identity_id != null ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.scalein_identity_id]
    }
  }

  # System-assigned identity fallback
  dynamic "identity" {
    for_each = var.scalein_identity_id == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  site_config {
    application_stack {
      powershell_core_version = var.function_config.powershell_version
    }

    application_insights_connection_string = azurerm_application_insights.scalein.connection_string
    application_insights_key               = azurerm_application_insights.scalein.instrumentation_key
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "powershell"
    "FUNCTIONS_EXTENSION_VERSION" = var.function_config.runtime_version

    # MI-based host storage — required when shared_access_key_enabled=false on the storage account
    "AzureWebJobsStorage__accountName" = var.storage_scalein_name
    "AzureWebJobsStorage__credential"  = "managedidentity"
    "AzureWebJobsStorage__clientId"    = var.managed_identity_client_id

    # Deployment mode — "1" = run from zip package. Works with key auth disabled
    # via the MI-authenticated host storage triple above. Kept in TF to prevent
    # drift removal by the authoritative app_settings map.
    "WEBSITE_RUN_FROM_PACKAGE" = "1"

    # VMSS reference
    "VMSS_NAME"           = var.resource_names.vmss
    "VMSS_RESOURCE_GROUP" = var.resource_group_name

    # Queue/table names used by GhWebHookScaleIn + ProcVmssScaleInQueue + ProcVmssDeleteAvailableVMs
    # Tables live in ScaleOut storage — accessed via SCALEOUT_STORAGE_NAME using cross-account table contributor role
    "STORAGE_ACCOUNT_NAME"   = var.storage_scalein_name
    "SCALEOUT_STORAGE_NAME"  = var.storage_scaleout_name
    "QUEUE_SCALEIN_NAME"     = var.scalein_queue_name
    "TABLE_AVAILABLE_NAME"   = var.table_available_name
    "TABLE_TRACKING_NAME"    = var.table_tracking_name
    "CLEANUP_TIMER_SCHEDULE" = var.cleanup_timer_schedule

    # Warm-pool cleanup tunables read by ProcVmssDeleteAvailableVMs.
    # POOL_TTL_MINUTES: idle window before a pooled VM is deleted.
    # POOL_CLEANUP_DRYRUN: "true" = log only; "false" = take action.
    # Default starts dry-run-true (fail closed); flipped per env after observation.
    "POOL_TTL_MINUTES"    = tostring(var.pool_ttl_minutes)
    "POOL_CLEANUP_DRYRUN" = tostring(var.pool_cleanup_dryrun)

    # Phase 5 reconciliation — read by ProcVmssReconciliation timer.
    # RUNNER_SCOPE: org name OR owner/repo. Slash-detection in code picks
    # the GitHub endpoint (org-scoped vs repo-scoped runners API).
    # GITHUB_RECONCILE_TOKEN: KV reference. Currently reuses the same secret
    # as GITHUB_PAT (Option A per project owner 2026-04-26). Future swap to
    # a narrower-scope token is a one-line change here.
    # Activation lockstep: ScaleIn's function.json schedule must change from
    # "0 0 0 1 1 *" → "%RECONCILE_TIMER_SCHEDULE%" AFTER this TF apply.
    # See .claude/Docs/Tracking/2026-04-26-phase5-activation-lockstep.md.
    "RUNNER_SCOPE"                  = var.runner_scope
    "RECONCILE_TIMER_SCHEDULE"      = var.reconcile_timer_schedule
    "RECONCILE_AUTOFIX"             = tostring(var.reconcile_autofix)
    "RECONCILE_PENDING_TTL_MINUTES" = tostring(var.reconcile_pending_ttl_minutes)
    "RECONCILE_ATTR_TTL_MINUTES"    = tostring(var.reconcile_attr_ttl_minutes)
    "GITHUB_RECONCILE_TOKEN" = var.github_pat_secret_uri != null ? (
      var.managed_identity_client_id != null
      ? "@Microsoft.KeyVault(SecretUri=${var.github_pat_secret_uri};clientId=${var.managed_identity_client_id})"
      : "@Microsoft.KeyVault(SecretUri=${var.github_pat_secret_uri})"
    ) : ""
  }

  tags = var.tags

  # Dependencies
  depends_on = [
    azurerm_role_assignment.scalein_vm_contributor,
    azurerm_role_assignment.scalein_storage_blob,
    azurerm_role_assignment.scalein_storage_queue,
    azurerm_role_assignment.scalein_storage_table,
    azurerm_role_assignment.scalein_scaleout_table_contributor
  ]
}

# -----------------------------------------------------------------------------
# ScaleOut Webhook Function App (Arch B Phase 2B)
# -----------------------------------------------------------------------------
# Hosts GhWebHookScaleOut (HTTP trigger) ONLY. The existing scaleout app keeps
# ProcVmssScaleQueue (queue trigger) + the worker cap. Splitting compute lets
# webhook-side parallelism flow freely (parallel pool claims under burst load)
# while the queue side stays serialized until Phase 4B + ScaleOut sign-off
# allow the cap to come off.
#
# Shares with the existing scaleout function app:
#   - Service plan (azurerm_service_plan.scaleout)
#   - Application Insights (azurerm_application_insights.scaleout)
#   - Storage account (var.storage_scaleout_name)
#   - Runtime UAMI (var.scaleout_identity_id — resolves to shared UAMI in dev)
#   - All KV refs and runtime app_settings (minus the worker cap)
# -----------------------------------------------------------------------------

resource "azurerm_windows_function_app" "scaleout_webhook" {
  count = var.deploy_functions && var.deploy_scaleout_webhook_app ? 1 : 0

  name                = var.resource_names.func_scaleout_webhook
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.scaleout[0].id

  storage_account_name          = var.storage_scaleout_name
  storage_uses_managed_identity = true

  # Same KV reference identity as the queue processor — same shared UAMI in dev,
  # same dedicated scaleout UAMI in prod.
  key_vault_reference_identity_id = var.scaleout_identity_id

  dynamic "identity" {
    for_each = var.scaleout_identity_id != null ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.scaleout_identity_id]
    }
  }

  dynamic "identity" {
    for_each = var.scaleout_identity_id == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  site_config {
    application_stack {
      powershell_core_version = var.function_config.powershell_version
    }

    application_insights_connection_string = azurerm_application_insights.scaleout.connection_string
    application_insights_key               = azurerm_application_insights.scaleout.instrumentation_key
  }

  # NO WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT — this app scales freely so
  # parallel webhooks → parallel pool claims. Queue processor cap stays on
  # its own app until Phase 4B is verified end-to-end.
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "powershell"
    "FUNCTIONS_EXTENSION_VERSION" = var.function_config.runtime_version

    "AzureWebJobsStorage__accountName" = var.storage_scaleout_name
    "AzureWebJobsStorage__credential"  = "managedidentity"
    "AzureWebJobsStorage__clientId"    = var.managed_identity_client_id

    "WEBSITE_RUN_FROM_PACKAGE" = "1"

    "GITHUB_AUTH_STRATEGY"   = var.github_auth_strategy
    "GITHUB_APP_ID"          = var.github_app_id
    "GITHUB_INSTALLATION_ID" = var.github_installation_id
    "GITHUB_ORGANIZATION"    = var.github_organization

    "GITHUB_PRIVATE_KEY" = var.github_private_key_secret_uri != null ? (
      var.managed_identity_client_id != null
      ? "@Microsoft.KeyVault(SecretUri=${var.github_private_key_secret_uri};clientId=${var.managed_identity_client_id})"
      : "@Microsoft.KeyVault(SecretUri=${var.github_private_key_secret_uri})"
    ) : ""
    "GITHUB_PAT" = var.github_pat_secret_uri != null ? (
      var.managed_identity_client_id != null
      ? "@Microsoft.KeyVault(SecretUri=${var.github_pat_secret_uri};clientId=${var.managed_identity_client_id})"
      : "@Microsoft.KeyVault(SecretUri=${var.github_pat_secret_uri})"
    ) : ""

    "VMSS_NAME"           = var.resource_names.vmss
    "VMSS_RESOURCE_GROUP" = var.resource_group_name

    "STORAGE_ACCOUNT_NAME" = var.storage_scaleout_name
    "QUEUE_SCALEOUT_NAME"  = var.scaleout_queue_name
    "TABLE_AVAILABLE_NAME" = var.table_available_name
    "TABLE_TRACKING_NAME"  = var.table_tracking_name
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.scaleout_vm_contributor,
    azurerm_role_assignment.scaleout_storage_blob,
    azurerm_role_assignment.scaleout_storage_queue,
    azurerm_role_assignment.scaleout_storage_table,
    azurerm_role_assignment.scaleout_keyvault_secrets
  ]
}

