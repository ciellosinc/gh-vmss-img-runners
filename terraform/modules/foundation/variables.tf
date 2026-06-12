# -----------------------------------------------------------------------------
# Foundation Module Variables
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Environment Identifiers
# -----------------------------------------------------------------------------

variable "app" {
  type        = string
  description = "Application name identifier"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, test, prod)"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

variable "region" {
  type        = string
  description = "Region abbreviation for resource naming"
}

variable "unique_suffix" {
  type        = string
  description = "Deterministic suffix (from sub ID) for globally-unique resource names like DNS labels"
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

# -----------------------------------------------------------------------------
# Managed Identity Configuration
# -----------------------------------------------------------------------------

variable "identity_strategy" {
  type = object({
    create_vmss_identity     = bool
    create_scaleout_identity = bool
    create_scalein_identity  = bool
    use_shared_identity      = bool
  })
  description = "Identity creation strategy per environment"
}

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

variable "networking_config" {
  type = object({
    vnet_address_prefix   = string
    subnet_address_prefix = string
    lb_private_ip         = optional(string, "10.0.0.10")
  })
  description = "Networking configuration"
}

variable "nsg_rules" {
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  description = "NSG rules to apply"
}

# -----------------------------------------------------------------------------
# Compute Gallery Configuration
# -----------------------------------------------------------------------------

variable "gallery_config" {
  type = object({
    os_type            = optional(string, "Windows")
    os_state           = optional(string, "Generalized")
    hyper_v_generation = optional(string, "V1")
    architecture       = optional(string, "x64")
    image_publisher    = optional(string, "MicrosoftWindowsServer")
    image_offer        = optional(string, "WindowsServer")
    image_sku          = optional(string, "2022-datacenter-g2")
  })
  description = "Compute gallery configuration"
}

# -----------------------------------------------------------------------------
# Storage Configuration
# -----------------------------------------------------------------------------

variable "storage_config" {
  type = object({
    account_tier             = optional(string, "Standard")
    account_replication_type = optional(string, "LRS")
    account_kind             = optional(string, "StorageV2")
    access_tier              = optional(string, "Hot")
    min_tls_version          = optional(string, "TLS1_2")
  })
  description = "Storage account configuration"
}

# -----------------------------------------------------------------------------
# Log Analytics Configuration
# -----------------------------------------------------------------------------

variable "log_analytics_config" {
  type = object({
    sku               = optional(string, "PerGB2018")
    retention_in_days = optional(number, 30)
    daily_quota_gb    = optional(number, -1)
  })
  description = "Log Analytics workspace configuration"
}

# -----------------------------------------------------------------------------
# Resource Names (from shared module)
# -----------------------------------------------------------------------------

variable "resource_names" {
  type        = map(string)
  description = "Pre-generated resource names from shared module"
}

# -----------------------------------------------------------------------------
# Key Vault Configuration
# -----------------------------------------------------------------------------

variable "key_vault_config" {
  type = object({
    soft_delete_retention_days = optional(number, 90)
    purge_protection_enabled   = optional(bool, true)
    network_default_action     = optional(string, "Allow")
    allowed_ip_ranges          = optional(list(string), [])
  })
  description = "Key Vault configuration for GitHub secrets"
  default = {
    soft_delete_retention_days = 90
    purge_protection_enabled   = true
    network_default_action     = "Allow"
    allowed_ip_ranges          = []
  }
}

# -----------------------------------------------------------------------------
# GitHub Secrets (to store in Key Vault)
# -----------------------------------------------------------------------------

variable "github_private_key" {
  type        = string
  description = "GitHub App private key to store in Key Vault"
  sensitive   = true
  default     = ""
}

variable "github_pat" {
  type        = string
  description = "GitHub Personal Access Token to store in Key Vault"
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Log Analytics for Key Vault Diagnostics
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace ID for Key Vault diagnostics"
  default     = null
}

variable "create_keyvault_admin_role" {
  type        = bool
  description = "Whether to create Key Vault Administrator role for deployment identity. Requires User Access Administrator permission on the SP."
  default     = false
}

# -----------------------------------------------------------------------------
# Queue-Based Webhook Scaling Configuration
# -----------------------------------------------------------------------------

variable "scaling_queue_names" {
  type = object({
    scaleout = string
    scalein  = string
  })
  description = "Storage queue names for the webhook-driven scaling architecture"
  default = {
    scaleout = "vmss-scale-requests"
    scalein  = "vmss-scale-in-requests"
  }
}

variable "scaling_table_names" {
  type = object({
    available          = string
    tracking           = string
    pending            = string
    reconcile_tracking = string
  })
  description = "Storage table names for VM availability pool, job tracking, pending self-attribution, and reconciliation drift tracking"
  default = {
    available          = "VmssScaleAvailable"
    tracking           = "VmssScaleTracking"
    pending            = "VmssScalePending"
    reconcile_tracking = "VmssReconcileTracking"
  }
}

# -----------------------------------------------------------------------------
# Deploy Identity (UNIFIED) — single UAMI federating all consumer repo deploys
# -----------------------------------------------------------------------------
# See modules/foundation/deploy-identities.tf for the rationale + handoff doc.

variable "create_unified_deploy_identity" {
  type        = bool
  description = "Create the single shared UAMI (id-ghrunners-deploy) with FICs for all consumer repo deploy environments. Replaces the per-app deploy UAMIs that existed before 2026-04-27."
  default     = false
}

variable "deploy_identity_location" {
  type        = string
  description = "Azure region for the unified deploy UAMI. Defaults to module location."
  default     = null
}

variable "github_secrets_pat" {
  type        = string
  description = "Fine-grained GitHub PAT scoped to eh-ciellos/ScaleInVmssFunction and eh-ciellos/ScaleOutVmssFunction with Secrets:Read+Write. Used by the github provider to push AZURE_CLIENT_ID env secrets in lockstep with the unified deploy UAMI's clientId. When empty, env secrets are NOT TF-managed (consumer repos retain manually-set values)."
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Image Builder Identity (OIDC migration for gitspacecadet/vm-runner-image)
# -----------------------------------------------------------------------------
# Separate UAMI from id-ghrunners-deploy because Packer needs sub-wide
# Contributor (creates temp RGs, attaches images to gallery) while function-
# app deploys only need scoped roles. Mixing inflates blast radius for both
# principals. Federated via environment:image-build on the consumer repo
# (any branch allowed by GH env protection rules). See FromVmImageAgent/21.

variable "create_image_builder_identity" {
  type        = bool
  description = "Create the dedicated id-ghrunners-image-builder UAMI + its FIC + sub-wide Contributor role assignment. Replaces the legacy gh-runner-image-builder SP + client-secret auth on gitspacecadet/vm-runner-image with OIDC."
  default     = false
}

# -----------------------------------------------------------------------------
# RDP Access Configuration (Dev Only)
# -----------------------------------------------------------------------------

variable "enable_rdp_access" {
  type        = bool
  description = "Enable RDP access via public IP and NAT rules (dev environment only)"
  default     = false
}
