# -----------------------------------------------------------------------------
# Foundation Module Outputs
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Managed Identity Outputs
# -----------------------------------------------------------------------------

output "vmss_identity_id" {
  description = "VMSS managed identity resource ID"
  value       = local.vmss_identity_id
}

output "vmss_identity_principal_id" {
  description = "VMSS managed identity principal ID"
  value       = local.vmss_identity_principal_id
}

output "scaleout_identity_id" {
  description = "ScaleOut function managed identity resource ID"
  value       = local.scaleout_identity_id
}

output "scaleout_identity_principal_id" {
  description = "ScaleOut function managed identity principal ID"
  value       = local.scaleout_identity_principal_id
}

output "scalein_identity_id" {
  description = "ScaleIn function managed identity resource ID"
  value       = local.scalein_identity_id
}

output "scalein_identity_principal_id" {
  description = "ScaleIn function managed identity principal ID"
  value       = local.scalein_identity_principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the active managed identity used by Function Apps (shared in dev/test, scaleout in prod)"
  value = var.identity_strategy.use_shared_identity ? (
    length(azurerm_user_assigned_identity.shared) > 0 ? azurerm_user_assigned_identity.shared[0].client_id : null
    ) : (
    length(azurerm_user_assigned_identity.scaleout) > 0 ? azurerm_user_assigned_identity.scaleout[0].client_id : null
  )
}

output "deploy_identity_id" {
  description = "Resource ID of the unified deploy UAMI (id-ghrunners-deploy)."
  value       = length(azurerm_user_assigned_identity.deploy) > 0 ? azurerm_user_assigned_identity.deploy[0].id : null
}

output "deploy_identity_principal_id" {
  description = "Principal ID of the unified deploy UAMI. Consumed by Website Contributor role assignments on each function app in runtime/role-assignments.tf."
  value       = length(azurerm_user_assigned_identity.deploy) > 0 ? azurerm_user_assigned_identity.deploy[0].principal_id : null
}

output "deploy_identity_client_id" {
  description = "Client ID of the unified deploy UAMI. Pushed to consumer repos' AZURE_CLIENT_ID env secrets via TF-managed github_actions_environment_secret resources (Option A) when github_secrets_pat is provided."
  value       = length(azurerm_user_assigned_identity.deploy) > 0 ? azurerm_user_assigned_identity.deploy[0].client_id : null
}

output "image_builder_client_id" {
  description = "Client ID of the image-builder UAMI (id-ghrunners-image-builder). Pushed to gitspacecadet/vm-runner-image's repo-level AZURE_CLIENT_ID secret by the root module via github.image_builder_scope provider alias. Null when create_image_builder_identity is false."
  value       = length(azurerm_user_assigned_identity.image_builder) > 0 ? azurerm_user_assigned_identity.image_builder[0].client_id : null
}

# -----------------------------------------------------------------------------
# Networking Outputs
# -----------------------------------------------------------------------------

output "vnet_id" {
  description = "Virtual network resource ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "Subnet resource ID"
  value       = azurerm_subnet.runners.id
}

output "subnet_name" {
  description = "Subnet name"
  value       = azurerm_subnet.runners.name
}

output "nsg_id" {
  description = "Network security group resource ID"
  value       = azurerm_network_security_group.main.id
}

output "lb_id" {
  description = "Load balancer resource ID"
  value       = azurerm_lb.main.id
}

output "lb_backend_pool_id" {
  description = "Load balancer backend pool resource ID"
  value       = azurerm_lb_backend_address_pool.main.id
}

output "public_ip_address" {
  description = "Public IP address for outbound SNAT"
  value       = azurerm_public_ip.outbound.ip_address
}

# -----------------------------------------------------------------------------
# Compute Gallery Outputs
# -----------------------------------------------------------------------------

output "gallery_id" {
  description = "Shared image gallery resource ID"
  value       = azurerm_shared_image_gallery.main.id
}

output "gallery_name" {
  description = "Shared image gallery name"
  value       = azurerm_shared_image_gallery.main.name
}

output "image_definition_id" {
  description = "Image definition resource ID"
  value       = azurerm_shared_image.runner.id
}

output "image_definition_name" {
  description = "Image definition name"
  value       = azurerm_shared_image.runner.name
}

# -----------------------------------------------------------------------------
# Storage Outputs
# -----------------------------------------------------------------------------

output "storage_scaleout_id" {
  description = "ScaleOut storage account resource ID"
  value       = azurerm_storage_account.scaleout.id
}

output "storage_scaleout_name" {
  description = "ScaleOut storage account name"
  value       = azurerm_storage_account.scaleout.name
}

output "storage_scalein_id" {
  description = "ScaleIn storage account resource ID"
  value       = azurerm_storage_account.scalein.id
}

output "storage_scalein_name" {
  description = "ScaleIn storage account name"
  value       = azurerm_storage_account.scalein.name
}

# -----------------------------------------------------------------------------
# Log Analytics Outputs
# -----------------------------------------------------------------------------

output "log_analytics_id" {
  description = "Log Analytics workspace resource ID"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID (GUID)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_name" {
  description = "Log Analytics workspace name"
  value       = azurerm_log_analytics_workspace.main.name
}

# -----------------------------------------------------------------------------
# Key Vault Outputs
# -----------------------------------------------------------------------------

output "key_vault_id" {
  description = "Key Vault resource ID"
  value       = azurerm_key_vault.github_secrets.id
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.github_secrets.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.github_secrets.vault_uri
}

output "github_private_key_secret_uri" {
  description = "Secret URI for GitHub private key (with version)"
  value       = length(azurerm_key_vault_secret.github_private_key) > 0 ? azurerm_key_vault_secret.github_private_key[0].versionless_id : null
  sensitive   = true
}

output "github_pat_secret_uri" {
  description = "Secret URI for GitHub PAT (with version)"
  value       = length(azurerm_key_vault_secret.github_pat) > 0 ? azurerm_key_vault_secret.github_pat[0].versionless_id : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# VMSS Script Outputs
# -----------------------------------------------------------------------------

output "runner_script_url" {
  description = "Blob URL for Initialize-GhRunner.ps1 (downloaded by VMSS extension at boot)"
  value       = azurerm_storage_blob.runner_init_script.url
}

# -----------------------------------------------------------------------------
# Queue-Based Webhook Scaling Outputs
# -----------------------------------------------------------------------------

output "scaleout_queue_name" {
  description = "Name of the scale-out request queue (vmss-scale-requests)"
  value       = azurerm_storage_queue.scaleout_requests.name
}

output "scalein_queue_name" {
  description = "Name of the scale-in request queue (vmss-scale-in-requests)"
  value       = azurerm_storage_queue.scalein_requests.name
}

output "table_available_name" {
  description = "Name of the VM availability pool table (VmssScaleAvailable)"
  value       = azapi_resource.vmss_scale_available.name
}

output "table_tracking_name" {
  description = "Name of the job-to-VM tracking table (VmssScaleTracking)"
  value       = azapi_resource.vmss_scale_tracking.name
}

output "table_pending_name" {
  description = "Name of the pending self-attribution table (VmssScalePending)"
  value       = azapi_resource.vmss_scale_pending.name
}

output "table_reconcile_tracking_name" {
  description = "Name of the reconciliation drift-tracking table (VmssReconcileTracking, Phase 5)"
  value       = azapi_resource.vmss_reconcile_tracking.name
}

# -----------------------------------------------------------------------------
# RDP Access Outputs (Dev Only)
# -----------------------------------------------------------------------------

output "lb_nat_pool_id" {
  description = "Load balancer NAT pool ID for RDP access"
  value       = var.enable_rdp_access && length(azurerm_lb_nat_pool.rdp) > 0 ? azurerm_lb_nat_pool.rdp[0].id : null
}

output "rdp_public_ip" {
  description = "Public IP address for RDP access (dev only)"
  value       = var.enable_rdp_access && length(azurerm_public_ip.inbound) > 0 ? azurerm_public_ip.inbound[0].ip_address : null
}

output "rdp_fqdn" {
  description = "FQDN for RDP access (dev only)"
  value       = var.enable_rdp_access && length(azurerm_public_ip.inbound) > 0 ? azurerm_public_ip.inbound[0].fqdn : null
}
