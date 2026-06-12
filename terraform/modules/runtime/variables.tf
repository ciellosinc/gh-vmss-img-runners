# -----------------------------------------------------------------------------
# Runtime Module Variables
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
}

variable "region" {
  type        = string
  description = "Region abbreviation for resource naming"
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "resource_group_id" {
  type        = string
  description = "Resource group ID for RBAC scoping"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID for constructing resource IDs"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

# -----------------------------------------------------------------------------
# Resource Names (from shared module)
# -----------------------------------------------------------------------------

variable "resource_names" {
  type        = map(string)
  description = "Pre-generated resource names from shared module"
}

# -----------------------------------------------------------------------------
# Deployment Control
# -----------------------------------------------------------------------------

variable "deploy_vmss" {
  type        = bool
  description = "Whether to deploy VMSS"
  default     = true
}

variable "deploy_functions" {
  type        = bool
  description = "Whether to deploy Function Apps"
  default     = true
}

# -----------------------------------------------------------------------------
# Foundation References
# -----------------------------------------------------------------------------

variable "subnet_id" {
  type        = string
  description = "Subnet ID for VMSS deployment"
}

variable "lb_backend_pool_id" {
  type        = string
  description = "Load balancer backend pool ID"
}

variable "log_analytics_id" {
  type        = string
  description = "Log Analytics workspace ID"
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace GUID"
}

variable "gallery_name" {
  type        = string
  description = "Compute gallery name"
}

variable "image_definition_name" {
  type        = string
  description = "Image definition name"
}

variable "image_version" {
  type        = string
  description = "Image version to deploy"
}

variable "storage_scaleout_id" {
  type        = string
  description = "ScaleOut storage account ID"
}

variable "storage_scaleout_name" {
  type        = string
  description = "ScaleOut storage account name"
}

variable "storage_scalein_id" {
  type        = string
  description = "ScaleIn storage account ID"
}

variable "storage_scalein_name" {
  type        = string
  description = "ScaleIn storage account name"
}

# -----------------------------------------------------------------------------
# Identity References
# -----------------------------------------------------------------------------

variable "vmss_identity_id" {
  type        = string
  description = "VMSS managed identity ID"
  default     = null
}

variable "vmss_identity_principal_id" {
  type        = string
  description = "VMSS managed identity principal ID"
  default     = null
}

variable "scaleout_identity_id" {
  type        = string
  description = "ScaleOut function managed identity ID"
  default     = null
}

variable "scaleout_identity_principal_id" {
  type        = string
  description = "ScaleOut function managed identity principal ID"
  default     = null
}

variable "scalein_identity_id" {
  type        = string
  description = "ScaleIn function managed identity ID"
  default     = null
}

variable "scalein_identity_principal_id" {
  type        = string
  description = "ScaleIn function managed identity principal ID"
  default     = null
}

# Role Assignment Control Flags
# These are known at plan time and avoid the "count depends on computed value" error
variable "create_vmss_role_assignments" {
  type        = bool
  description = "Whether to create VMSS identity role assignments"
  default     = false
}

variable "create_scaleout_role_assignments" {
  type        = bool
  description = "Whether to create ScaleOut identity role assignments"
  default     = false
}

variable "create_scalein_role_assignments" {
  type        = bool
  description = "Whether to create ScaleIn identity role assignments (RG-scoped roles)"
  default     = false
}

variable "create_scalein_storage_role_assignments" {
  type        = bool
  description = "Whether to create ScaleIn storage-scoped role assignments (Blob/Queue/Table on ScaleIn storage — never duplicates of ScaleOut roles)"
  default     = false
}

# -----------------------------------------------------------------------------
# VMSS Configuration
# -----------------------------------------------------------------------------

variable "vmss_config" {
  type = object({
    vm_size                      = string
    min_capacity                 = number
    max_capacity                 = number
    initial_capacity             = number
    admin_username               = string
    os_disk_size_gb              = optional(number, 256)
    os_disk_storage_account_type = string
  })
  description = "VMSS configuration"
}

variable "vmss_admin_password" {
  type        = string
  description = "VMSS admin password"
  sensitive   = true
}

variable "vmss_computer_name_prefix" {
  type        = string
  description = "Computer name prefix for VMSS instances (max 9 chars for Windows)"

  validation {
    condition     = length(var.vmss_computer_name_prefix) <= 9
    error_message = "computer_name_prefix must be at most 9 characters for Windows VMSS"
  }
}

# -----------------------------------------------------------------------------
# Function App Configuration
# -----------------------------------------------------------------------------

variable "function_config" {
  type = object({
    runtime_version    = string
    powershell_version = string
    os_type            = string
    sku_name           = string
  })
  description = "Function App configuration"
}

# -----------------------------------------------------------------------------
# GitHub Configuration
# -----------------------------------------------------------------------------

variable "github_auth_strategy" {
  type        = string
  description = "GitHub authentication strategy"
}

variable "github_app_id" {
  type        = string
  description = "GitHub App ID"
  default     = ""
}

variable "github_installation_id" {
  type        = string
  description = "GitHub App Installation ID"
  default     = ""
}

variable "github_private_key" {
  type        = string
  description = "GitHub App private key"
  sensitive   = true
  default     = ""
}

variable "github_pat" {
  type        = string
  description = "GitHub Personal Access Token"
  sensitive   = true
  default     = ""
}

variable "github_organization" {
  type        = string
  description = "GitHub organization name"
  default     = ""
}

# -----------------------------------------------------------------------------
# Key Vault References
# -----------------------------------------------------------------------------

variable "key_vault_id" {
  type        = string
  description = "Key Vault resource ID for RBAC assignments"
}

variable "github_private_key_secret_uri" {
  type        = string
  description = "Key Vault secret URI for GitHub private key"
  default     = null
  sensitive   = true
}

variable "github_pat_secret_uri" {
  type        = string
  description = "Key Vault secret URI for GitHub PAT"
  default     = null
  sensitive   = true
}

variable "managed_identity_client_id" {
  type        = string
  description = "Client ID of the user-assigned managed identity — used in AzureWebJobsStorage__clientId and KV reference clientId"
  default     = null
}

# -----------------------------------------------------------------------------
# Queue-Based Webhook Scaling
# -----------------------------------------------------------------------------

variable "scaleout_queue_name" {
  type        = string
  description = "Name of the storage queue that buffers scale-out requests (vmss-scale-requests)"
  default     = "vmss-scale-requests"
}

variable "scalein_queue_name" {
  type        = string
  description = "Name of the storage queue that buffers scale-in requests (vmss-scale-in-requests)"
  default     = "vmss-scale-in-requests"
}

variable "table_available_name" {
  type        = string
  description = "Name of the table tracking idle/available VM instances (VmssScaleAvailable)"
  default     = "VmssScaleAvailable"
}

variable "table_tracking_name" {
  type        = string
  description = "Name of the table mapping workflow_run_id to VmInstanceId (VmssScaleTracking)"
  default     = "VmssScaleTracking"
}

variable "cleanup_timer_schedule" {
  type        = string
  description = "CRON schedule for ProcVmssDeleteAvailableVMs cleanup function (every 5 min)"
  default     = "0 */5 * * * *"
}

# -----------------------------------------------------------------------------
# VMSS Runner Registration Extension
# -----------------------------------------------------------------------------

variable "runner_script_url" {
  type        = string
  description = "Blob URL for Initialize-GhRunner.ps1 (downloaded by VMSS extension at boot via MI auth)"
  default     = null
}

# -----------------------------------------------------------------------------
# Function App — Warm Pool Cleanup (ScaleIn)
# -----------------------------------------------------------------------------

variable "pool_ttl_minutes" {
  type        = number
  description = "Idle minutes before the warm-pool cleanup timer deletes a pooled VM."
  default     = 15
}

variable "pool_cleanup_dryrun" {
  type        = bool
  description = "If true, the cleanup timer logs would-delete targets without taking action."
  default     = true
}

# -----------------------------------------------------------------------------
# Function App — ScaleOut Worker Cap
# -----------------------------------------------------------------------------

variable "scaleout_max_scale_out_workers" {
  type        = number
  description = "Caps the ScaleOut function app's concurrent workers (WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT). Null = setting omitted."
  default     = null
}

# -----------------------------------------------------------------------------
# Unified Deploy UAMI — single identity for ScaleIn + ScaleOut webhook CI/CD
# -----------------------------------------------------------------------------

variable "deploy_identity_principal_id" {
  type        = string
  description = "Principal ID of the unified deploy UAMI (from foundation). One principal grants Website Contributor on every function app it deploys. Null when create_unified_deploy_identity=false."
  default     = null
}

variable "create_unified_deploy_role_assignments" {
  type        = bool
  description = "Static flag (known at plan time) that gates the unified deploy UAMI's Website Contributor role assignments on each function app. Mirrors create_unified_deploy_identity at the root level. Required because count cannot depend on the UAMI principal_id (only known after apply)."
  default     = false
}

# -----------------------------------------------------------------------------
# Phase 2B — ScaleOut Webhook Function App
# -----------------------------------------------------------------------------

variable "deploy_scaleout_webhook_app" {
  type        = bool
  description = "Provision the dedicated webhook-handler function app (Arch B Phase 2B). Shares plan/storage/runtime UAMI with the queue processor; no worker cap."
  default     = false
}

# -----------------------------------------------------------------------------
# Phase 5 — Reconciliation timer settings (read by ScaleIn's ProcVmssReconciliation)
# -----------------------------------------------------------------------------

variable "runner_scope" {
  type        = string
  description = "Runner scope value (org name OR owner/repo). Empty disables Phase 5 settings on the function app."
  default     = ""
}

variable "reconcile_timer_schedule" {
  type        = string
  description = "Cron for the reconciliation timer."
  default     = "0 */15 * * * *"
}

variable "reconcile_autofix" {
  type        = bool
  description = "Read-only (false) vs auto-fix (true) for the reconciliation timer."
  default     = false
}

variable "reconcile_pending_ttl_minutes" {
  type        = number
  description = "TTL (minutes) for pending rows past which reconciliation flags/cleans them."
  default     = 10
}

variable "reconcile_attr_ttl_minutes" {
  type        = number
  description = "TTL (minutes) for stuck pending_attribution tracking rows."
  default     = 5
}

# -----------------------------------------------------------------------------
# RDP Access Configuration (Dev Only)
# -----------------------------------------------------------------------------

variable "lb_nat_pool_id" {
  type        = string
  description = "Load balancer NAT pool ID for RDP access (optional, dev only)"
  default     = null
}
