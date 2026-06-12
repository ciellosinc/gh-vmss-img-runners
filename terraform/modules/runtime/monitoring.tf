# -----------------------------------------------------------------------------
# Application Insights - Runtime Module
# Creates monitoring for ScaleOut and ScaleIn function apps
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ScaleOut Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_application_insights" "scaleout" {
  name                = var.resource_names.appi_scaleout
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.log_analytics_id
  application_type    = "web"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ScaleIn Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_application_insights" "scalein" {
  name                = var.resource_names.appi_scalein
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.log_analytics_id
  application_type    = "web"

  tags = var.tags
}
