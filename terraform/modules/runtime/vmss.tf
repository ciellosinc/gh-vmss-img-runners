# -----------------------------------------------------------------------------
# Virtual Machine Scale Set - Runtime Module
# Creates Windows VMSS for GitHub self-hosted runners
# -----------------------------------------------------------------------------

# Construct image reference ID. When image_version is "latest" (or empty), use the
# image DEFINITION ID (no /versions/...) — Azure resolves to the latest non-excluded
# version at VMSS creation / instance reimage. Otherwise pin to a specific version.
#
# Definition ID format: /subscriptions/{sub}/.../galleries/{gallery}/images/{image}
# Version ID format:    /subscriptions/{sub}/.../galleries/{gallery}/images/{image}/versions/{version}
locals {
  image_base_id     = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Compute/galleries/${var.gallery_name}/images/${var.image_definition_name}"
  use_latest_image  = var.image_version == "" || lower(var.image_version) == "latest"
  resolved_image_id = local.use_latest_image ? local.image_base_id : "${local.image_base_id}/versions/${var.image_version}"
}


# -----------------------------------------------------------------------------
# Windows Virtual Machine Scale Set
# -----------------------------------------------------------------------------

resource "azurerm_windows_virtual_machine_scale_set" "main" {
  count = var.deploy_vmss ? 1 : 0

  name                 = var.resource_names.vmss
  computer_name_prefix = var.vmss_computer_name_prefix
  location             = var.location
  resource_group_name  = var.resource_group_name
  sku                  = var.vmss_config.vm_size
  instances            = var.vmss_config.initial_capacity

  admin_username = var.vmss_config.admin_username
  admin_password = var.vmss_admin_password

  # Upgrade policy
  upgrade_mode = "Manual"

  # Disable over-provisioning for cost optimization
  overprovision = false

  # Single placement group for smaller deployments
  single_placement_group = true

  # Zone balance (if using zones)
  zone_balance = false

  # Source image from gallery — resolves to latest version when image_version="latest" or ""
  source_image_id = local.resolved_image_id

  # OS Disk configuration
  os_disk {
    storage_account_type = var.vmss_config.os_disk_storage_account_type
    caching              = "ReadWrite"
    disk_size_gb         = var.vmss_config.os_disk_size_gb
  }

  # Network interface
  network_interface {
    name    = "nic-primary"
    primary = true

    ip_configuration {
      name                                   = "ipconfig-primary"
      primary                                = true
      subnet_id                              = var.subnet_id
      load_balancer_backend_address_pool_ids = [var.lb_backend_pool_id]
      load_balancer_inbound_nat_rules_ids    = var.lb_nat_pool_id != null ? [var.lb_nat_pool_id] : []
    }
  }

  # User-assigned managed identity
  dynamic "identity" {
    for_each = var.vmss_identity_id != null ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.vmss_identity_id]
    }
  }

  # System-assigned identity fallback (for dev)
  dynamic "identity" {
    for_each = var.vmss_identity_id == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  # Boot diagnostics (using managed storage)
  boot_diagnostics {}

  tags = var.tags

  # Lifecycle: Ignore changes to instances (managed by autoscaling)
  lifecycle {
    ignore_changes = [
      instances
    ]
  }

  # Dependencies: Wait for role assignments
  depends_on = [
    azurerm_role_assignment.vmss_network_contributor,
    azurerm_role_assignment.vmss_reader,
    azurerm_role_assignment.vmss_storage_blob_scaleout,
    azurerm_role_assignment.vmss_storage_table_scaleout
  ]
}

# -----------------------------------------------------------------------------
# Custom Script Extension — Runner Registration at Boot
# -----------------------------------------------------------------------------
# Downloads Initialize-GhRunner.ps1 from blob storage using the VMSS managed
# identity (no SAS, no key — shared_access_key_enabled=false on ScaleOut storage).
# The script authenticates to Azure via MI, retrieves the GitHub PAT from Key Vault,
# fetches a runner registration token from GitHub API, and registers the instance
# as a self-hosted runner.
#
# Dependency chain (no chicken-egg):
#   foundation: storage account → blob container → script upload → RBAC
#   runtime:    VMSS + this extension (blob URL passed as variable)
# -----------------------------------------------------------------------------

resource "azurerm_virtual_machine_scale_set_extension" "runner_init" {
  count = var.deploy_vmss ? 1 : 0

  name                         = "GhRunnerSetup"
  virtual_machine_scale_set_id = azurerm_windows_virtual_machine_scale_set.main[0].id
  publisher                    = "Microsoft.Compute"
  type                         = "CustomScriptExtension"
  type_handler_version         = "1.10"
  auto_upgrade_minor_version   = true

  settings = jsonencode({
    fileUris = [var.runner_script_url]
  })

  protected_settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell -ExecutionPolicy Bypass -File Initialize-GhRunner.ps1",
      "-keyVaultName ${var.resource_names.key_vault}",
      "-gitHubPatSecretName github-pat",
      "-gitHubOrg ${var.github_organization}",
      # Phase 4B self-attribution: VM claims own VmssScalePending row at boot.
      "-storageAccountName ${var.storage_scaleout_name}",
      "-vmssName ${var.resource_names.vmss}"
    ])
    managedIdentity = var.managed_identity_client_id != null ? {
      clientId = var.managed_identity_client_id
    } : {}
  })
}

