# -----------------------------------------------------------------------------
# Key Vault - Foundation Module
# Stores GitHub secrets securely with RBAC-based access
# -----------------------------------------------------------------------------

# Get current Azure client configuration for Key Vault admin access
data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Key Vault Resource
# -----------------------------------------------------------------------------

resource "azurerm_key_vault" "github_secrets" {
  name                = var.resource_names.key_vault
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # SKU: standard for most use cases, premium for HSM-backed keys
  sku_name = "standard"

  # Security settings
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  # RBAC authorization (recommended over access policies)
  enable_rbac_authorization = true

  # Production-ready settings
  soft_delete_retention_days = var.key_vault_config.soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_config.purge_protection_enabled

  # Network security - allow Azure services
  network_acls {
    bypass                     = "AzureServices"
    default_action             = var.key_vault_config.network_default_action
    ip_rules                   = var.key_vault_config.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Role Assignment: Key Vault Secrets Officer for deployment identity
# -----------------------------------------------------------------------------
# KV uses RBAC authorization (enable_rbac_authorization = true). Contributor
# on the sub does NOT grant secret data-plane access. This role lets the
# deployer SP create/read/update/delete secrets within the same apply.
# Always created — the deployer needs this to write github-pat/github-private-key.

resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  scope                = azurerm_key_vault.github_secrets.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -----------------------------------------------------------------------------
# GitHub Secrets
# -----------------------------------------------------------------------------
# Store GitHub credentials securely in Key Vault

# GitHub App Private Key (for GitHubApp auth strategy)
resource "azurerm_key_vault_secret" "github_private_key" {
  count = var.github_private_key != "" ? 1 : 0

  name         = "github-private-key"
  value        = var.github_private_key
  key_vault_id = azurerm_key_vault.github_secrets.id

  content_type = "text/plain"

  tags = merge(var.tags, {
    Purpose = "GitHub App Authentication"
    Secret  = "PrivateKey"
  })

  depends_on = [azurerm_role_assignment.keyvault_secrets_officer]
}

# GitHub PAT (for PAT auth strategy)
resource "azurerm_key_vault_secret" "github_pat" {
  count = var.github_pat != "" ? 1 : 0

  name         = "github-pat"
  value        = var.github_pat
  key_vault_id = azurerm_key_vault.github_secrets.id

  content_type = "text/plain"

  tags = merge(var.tags, {
    Purpose = "GitHub PAT Authentication"
    Secret  = "PersonalAccessToken"
  })

  depends_on = [azurerm_role_assignment.keyvault_secrets_officer]
}

# -----------------------------------------------------------------------------
# Diagnostic Settings for Key Vault
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${var.resource_names.key_vault}"
  target_resource_id         = azurerm_key_vault.github_secrets.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
