# -----------------------------------------------------------------------------
# Root Module Outputs - GitHub VMSS Runners Infrastructure
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "vmss_name" {
  description = "Name of the Virtual Machine Scale Set"
  value       = module.runtime.vmss_name
}

output "vmss_id" {
  description = "ID of the Virtual Machine Scale Set"
  value       = module.runtime.vmss_id
  sensitive   = true
}

output "func_scaleout_hostname" {
  description = "Default hostname for the ScaleOut Function App"
  value       = module.runtime.func_scaleout_default_hostname
}

output "func_scalein_hostname" {
  description = "Default hostname for the ScaleIn Function App"
  value       = module.runtime.func_scalein_default_hostname
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = module.foundation.vnet_id
}

output "subnet_id" {
  description = "ID of the Subnet"
  value       = module.foundation.subnet_id
}

output "gallery_name" {
  description = "Name of the Azure Compute Gallery"
  value       = module.foundation.gallery_name
}

output "image_definition_name" {
  description = "Name of the image definition in the gallery"
  value       = module.foundation.image_definition_name
}

output "log_analytics_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = module.foundation.log_analytics_workspace_id
  sensitive   = true
}

output "key_vault_id" {
  description = "ID of the Key Vault for GitHub secrets"
  value       = module.foundation.key_vault_id
}

output "key_vault_name" {
  description = "Name of the Key Vault for GitHub secrets"
  value       = module.foundation.key_vault_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.foundation.key_vault_uri
}

# -----------------------------------------------------------------------------
# Phase 2B — ScaleOut Webhook Function App + Deploy Identity
# -----------------------------------------------------------------------------
# Surfaces post-apply for the ScaleOut agent (deploy workflow matrix wiring)
# and project owner (GitHub repo webhook URL repointing).

output "scaleout_webhook_function_name" {
  description = "Name of the ScaleOut webhook function app — for ScaleOut deploy workflow matrix"
  value       = module.runtime.func_scaleout_webhook_name
}

output "scaleout_webhook_function_url" {
  description = "Full https URL of the ScaleOut webhook function app. Project owner repoints GitHub repo webhooks to /api/ghwebhookscaleout under this host."
  value       = module.runtime.func_scaleout_webhook_url
}

output "deploy_client_id" {
  description = "Client ID of the unified deploy UAMI (id-ghrunners-deploy). Auto-pushed to ScaleIn (production env) and ScaleOut (webhook-production env) repos as AZURE_CLIENT_ID via the github provider when github_secrets_pat is set; otherwise set manually."
  value       = module.foundation.deploy_identity_client_id
}

# -----------------------------------------------------------------------------
# RDP Connection Info (Dev Environment Only)
# -----------------------------------------------------------------------------

output "rdp_connection_info" {
  description = "RDP connection information for dev environment"
  value = local.enable_rdp ? {
    public_ip    = module.foundation.rdp_public_ip
    fqdn         = module.foundation.rdp_fqdn
    port_range   = "50000-50099"
    instructions = <<-EOT
      To connect to VMSS instance N via RDP:
      1. Use public IP: ${module.foundation.rdp_public_ip}
      2. Port: 5000N (instance 0 = 50000, instance 1 = 50001, etc.)
      3. Username: ${local.vmss_config.admin_username}
      4. Command: mstsc /v:${module.foundation.rdp_public_ip}:50000
    EOT
  } : null
}
