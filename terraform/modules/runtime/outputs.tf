# -----------------------------------------------------------------------------
# Runtime Module Outputs
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# VMSS Outputs
# -----------------------------------------------------------------------------

output "vmss_id" {
  description = "VMSS resource ID"
  value       = var.deploy_vmss ? azurerm_windows_virtual_machine_scale_set.main[0].id : null
}

output "vmss_name" {
  description = "VMSS name"
  value       = var.deploy_vmss ? azurerm_windows_virtual_machine_scale_set.main[0].name : null
}

output "vmss_unique_id" {
  description = "VMSS unique ID"
  value       = var.deploy_vmss ? azurerm_windows_virtual_machine_scale_set.main[0].unique_id : null
}

# -----------------------------------------------------------------------------
# Function App Outputs
# -----------------------------------------------------------------------------

output "func_scaleout_id" {
  description = "ScaleOut function app resource ID"
  value       = var.deploy_functions ? azurerm_windows_function_app.scaleout[0].id : null
}

output "func_scaleout_name" {
  description = "ScaleOut function app name"
  value       = var.deploy_functions ? azurerm_windows_function_app.scaleout[0].name : null
}

output "func_scaleout_default_hostname" {
  description = "ScaleOut function app default hostname"
  value       = var.deploy_functions ? azurerm_windows_function_app.scaleout[0].default_hostname : null
}

output "func_scalein_id" {
  description = "ScaleIn function app resource ID"
  value       = var.deploy_functions ? azurerm_windows_function_app.scalein[0].id : null
}

output "func_scalein_name" {
  description = "ScaleIn function app name"
  value       = var.deploy_functions ? azurerm_windows_function_app.scalein[0].name : null
}

output "func_scalein_default_hostname" {
  description = "ScaleIn function app default hostname"
  value       = var.deploy_functions ? azurerm_windows_function_app.scalein[0].default_hostname : null
}

# Phase 2B — ScaleOut webhook app outputs

output "func_scaleout_webhook_id" {
  description = "ScaleOut webhook function app resource ID (null when deploy_scaleout_webhook_app=false)"
  value       = length(azurerm_windows_function_app.scaleout_webhook) > 0 ? azurerm_windows_function_app.scaleout_webhook[0].id : null
}

output "func_scaleout_webhook_name" {
  description = "ScaleOut webhook function app name (used by ScaleOut deploy workflow matrix)"
  value       = length(azurerm_windows_function_app.scaleout_webhook) > 0 ? azurerm_windows_function_app.scaleout_webhook[0].name : null
}

output "func_scaleout_webhook_url" {
  description = "Full https URL of the ScaleOut webhook function app. Project owner repoints GitHub repo webhooks to /api/ghwebhookscaleout under this host."
  value       = length(azurerm_windows_function_app.scaleout_webhook) > 0 ? "https://${azurerm_windows_function_app.scaleout_webhook[0].default_hostname}" : null
}

# -----------------------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------------------

output "appi_scaleout_id" {
  description = "ScaleOut Application Insights resource ID"
  value       = azurerm_application_insights.scaleout.id
}

output "appi_scaleout_connection_string" {
  description = "ScaleOut Application Insights connection string"
  value       = azurerm_application_insights.scaleout.connection_string
  sensitive   = true
}

output "appi_scalein_id" {
  description = "ScaleIn Application Insights resource ID"
  value       = azurerm_application_insights.scalein.id
}

output "appi_scalein_connection_string" {
  description = "ScaleIn Application Insights connection string"
  value       = azurerm_application_insights.scalein.connection_string
  sensitive   = true
}
