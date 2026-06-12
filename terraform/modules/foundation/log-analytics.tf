# -----------------------------------------------------------------------------
# Log Analytics Workspace - Foundation Module
# Creates central logging workspace for all monitoring
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.resource_names.log_analytics
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics_config.sku
  retention_in_days   = var.log_analytics_config.retention_in_days

  # Daily quota (-1 for unlimited)
  daily_quota_gb = var.log_analytics_config.daily_quota_gb >= 0 ? var.log_analytics_config.daily_quota_gb : null

  tags = var.tags
}
