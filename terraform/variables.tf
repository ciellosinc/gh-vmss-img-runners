# -----------------------------------------------------------------------------
# Root Variables - GitHub VMSS Runners Infrastructure
# -----------------------------------------------------------------------------
# All variables for the consolidated root module
# Environment-specific values are provided via tfvars files
# Usage: terraform plan -var-file=environments/dev.tfvars
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Environment Identifiers
# -----------------------------------------------------------------------------

variable "app" {
  type        = string
  description = "Application name identifier"
  default     = "ghrunners"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.app))
    error_message = "App name must be lowercase alphanumeric only."
  }
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
  default     = "cus"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.region))
    error_message = "Region must be 2-4 lowercase letters."
  }
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
  default     = "centralus"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources (merged with defaults)"
  default     = {}
}

# -----------------------------------------------------------------------------
# Deployment Control
# -----------------------------------------------------------------------------

variable "deploy_vmss" {
  type        = bool
  description = "Whether to deploy VMSS (requires image in gallery)"
  default     = true
}

variable "deploy_functions" {
  type        = bool
  description = "Whether to deploy Function Apps"
  default     = true
}

# -----------------------------------------------------------------------------
# Identity Strategy
# -----------------------------------------------------------------------------

variable "identity_strategy" {
  type = object({
    create_vmss_identity     = bool
    create_scaleout_identity = bool
    create_scalein_identity  = bool
    use_shared_identity      = bool
  })
  description = "Managed identity creation strategy for the environment"
  default = {
    create_vmss_identity     = false
    create_scaleout_identity = false
    create_scalein_identity  = false
    use_shared_identity      = false
  }

  # Guardrail: when use_shared_identity=true the resolver in
  # modules/foundation/managed-identity.tf always picks the shared MI, so any
  # dedicated MI created via create_*_identity is orphaned (no attachments, no
  # role assignments). Reject the combo at plan time instead of silently
  # wasting resources. See .claude/Docs/Tracking/2026-04-23-dev-mi-cleanup.md.
  validation {
    condition = !(var.identity_strategy.use_shared_identity && (
      var.identity_strategy.create_vmss_identity ||
      var.identity_strategy.create_scaleout_identity ||
      var.identity_strategy.create_scalein_identity
    ))
    error_message = "When use_shared_identity=true, all create_*_identity flags must be false. Dedicated MIs created under shared mode are never referenced by the resolver and become orphans."
  }
}

# -----------------------------------------------------------------------------
# VMSS Configuration
# -----------------------------------------------------------------------------

variable "vmss_vm_size" {
  type        = string
  description = "VM size for VMSS instances"
  default     = null # Uses default from defaults.tf
}

variable "vmss_min_capacity" {
  type        = number
  description = "Minimum VMSS instance count"
  default     = null

  validation {
    condition     = var.vmss_min_capacity == null || var.vmss_min_capacity >= 0
    error_message = "Minimum capacity must be >= 0."
  }
}

variable "vmss_max_capacity" {
  type        = number
  description = "Maximum VMSS instance count"
  default     = null

  validation {
    condition     = var.vmss_max_capacity == null || var.vmss_max_capacity >= 1
    error_message = "Maximum capacity must be >= 1."
  }
}

variable "vmss_initial_capacity" {
  type        = number
  description = "Initial VMSS instance count"
  default     = null

  validation {
    condition     = var.vmss_initial_capacity == null || var.vmss_initial_capacity >= 0
    error_message = "Initial capacity must be >= 0."
  }
}

variable "vmss_admin_username" {
  type        = string
  description = "Admin username for VMSS instances"
  default     = null
}

variable "vmss_admin_password" {
  type        = string
  description = "Admin password for VMSS instances"
  sensitive   = true
}

variable "os_disk_storage_account_type" {
  type        = string
  description = "OS disk storage type"
  default     = null

  validation {
    condition     = var.os_disk_storage_account_type == null || contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_storage_account_type)
    error_message = "Must be one of: Standard_LRS, StandardSSD_LRS, Premium_LRS."
  }
}

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

variable "vnet_address_prefix" {
  type        = string
  description = "VNet address prefix"
  default     = null
}

variable "subnet_address_prefix" {
  type        = string
  description = "Subnet address prefix"
  default     = null
}

# -----------------------------------------------------------------------------
# Storage Configuration
# -----------------------------------------------------------------------------

variable "storage_replication_type" {
  type        = string
  description = "Storage account replication type"
  default     = null

  validation {
    condition     = var.storage_replication_type == null || contains(["LRS", "ZRS", "GRS", "RAGRS"], var.storage_replication_type)
    error_message = "Must be one of: LRS, ZRS, GRS, RAGRS."
  }
}

# -----------------------------------------------------------------------------
# Compute Gallery Configuration
# -----------------------------------------------------------------------------

variable "hyper_v_generation" {
  type        = string
  description = "Hyper-V generation for image (V1 or V2)"
  default     = null

  validation {
    condition     = var.hyper_v_generation == null || contains(["V1", "V2"], var.hyper_v_generation)
    error_message = "Must be V1 or V2."
  }
}

variable "image_version" {
  type        = string
  description = "Image version for VMSS. Use 'latest' (or '') for auto-latest from the gallery definition, or a semver string like '1.0.0' to pin."
  default     = "latest"

  validation {
    condition     = var.image_version == "" || lower(var.image_version) == "latest" || can(regex("^\\d+\\.\\d+\\.\\d+$", var.image_version))
    error_message = "Image version must be 'latest', empty, or in semver format (e.g., 1.0.0)."
  }
}

variable "image_sku" {
  type        = string
  description = "Windows Server image SKU"
  default     = null
}

# -----------------------------------------------------------------------------
# GitHub Authentication
# -----------------------------------------------------------------------------

variable "github_auth_strategy" {
  type        = string
  description = "GitHub authentication strategy (GitHubApp or PAT)"
  default     = "GitHubApp"

  validation {
    condition     = contains(["GitHubApp", "PAT"], var.github_auth_strategy)
    error_message = "Must be GitHubApp or PAT."
  }
}

variable "github_app_id" {
  type        = string
  description = "GitHub App ID (required if using GitHubApp strategy)"
  default     = ""

  validation {
    condition     = var.github_app_id != "" || var.github_app_id == ""
    error_message = "GitHub App ID validation is handled by the github_auth_validation local."
  }
}

variable "github_installation_id" {
  type        = string
  description = "GitHub App Installation ID (required if using GitHubApp strategy)"
  default     = ""

  validation {
    condition     = var.github_installation_id != "" || var.github_installation_id == ""
    error_message = "GitHub Installation ID validation is handled by the github_auth_validation local."
  }
}

variable "github_private_key" {
  type        = string
  description = "GitHub App private key (required if using GitHubApp strategy)"
  sensitive   = true
  default     = ""
}

variable "github_pat" {
  type        = string
  description = "GitHub Personal Access Token (required if using PAT strategy)"
  sensitive   = true
  default     = ""
}

variable "github_organization" {
  type        = string
  description = "GitHub organization name"
  default     = ""
}

# -----------------------------------------------------------------------------
# Import Configuration (for existing resources)
# -----------------------------------------------------------------------------

variable "import_kv_secret_pat_version" {
  type        = string
  description = "Key Vault secret version ID for github-pat (for import). Leave empty to skip import and create new version."
  default     = ""
}

# -----------------------------------------------------------------------------
# Log Analytics Configuration
# -----------------------------------------------------------------------------

variable "log_analytics_retention_days" {
  type        = number
  description = "Log Analytics retention in days"
  default     = null

  validation {
    condition     = var.log_analytics_retention_days == null || (var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730)
    error_message = "Retention must be between 30 and 730 days."
  }
}

# -----------------------------------------------------------------------------
# Provider Configuration (for production)
# -----------------------------------------------------------------------------

variable "prevent_resource_group_deletion" {
  type        = bool
  description = "Prevent deletion of resource groups containing resources"
  default     = false
}

# -----------------------------------------------------------------------------
# Function App — Warm Pool Cleanup (ScaleIn)
# -----------------------------------------------------------------------------
# Codify the pool cleanup app settings on the ScaleIn function app so they
# don't drift on apply. ProcVmssDeleteAvailableVMs reads both at runtime.

variable "pool_ttl_minutes" {
  type        = number
  description = "Idle minutes before the warm-pool cleanup timer deletes a pooled VM. Tunable per env."
  default     = 15

  validation {
    condition     = var.pool_ttl_minutes >= 1 && var.pool_ttl_minutes <= 1440
    error_message = "pool_ttl_minutes must be between 1 and 1440."
  }
}

variable "pool_cleanup_dryrun" {
  type        = bool
  description = "If true, the cleanup timer logs would-delete targets without taking action. Default true (fail-closed); flip to false per env after observation window."
  default     = true
}

# -----------------------------------------------------------------------------
# Function App — ScaleOut Worker Cap
# -----------------------------------------------------------------------------
# Caps the function app's max worker count. Combined with host.json's
# batchSize=1 + newBatchThreshold=0, this gives true cross-worker
# serialization so parallel queue messages can't race on VMSS InstanceId
# sampling. Set to 1 in dev. Leave null in test/prod until explicitly opted in.

variable "scaleout_max_scale_out_workers" {
  type        = number
  description = "Value for WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT on the ScaleOut function app. Null = setting omitted (Azure defaults apply). 1 = single-worker serialization."
  default     = null

  validation {
    # Ternary form (not `== null || >= 1`) because TF 1.9 evaluates both sides
    # of `||` for validation analysis even when the LHS is true, which throws
    # "argument must not be null" on the >= when the var is unset.
    condition     = var.scaleout_max_scale_out_workers == null ? true : var.scaleout_max_scale_out_workers >= 1
    error_message = "scaleout_max_scale_out_workers must be >= 1 when set."
  }
}

# -----------------------------------------------------------------------------
# Deploy Identity (UNIFIED) — single UAMI federating all consumer repo deploys
# -----------------------------------------------------------------------------
# Replaces the per-app deploy UAMIs (id-scalein-ghrunners-deploy +
# id-scaleout-webhook-ghrunners-deploy) with a single id-ghrunners-deploy
# UAMI. All consumer repos use the same AZURE_CLIENT_ID. Per-function role
# assignments preserve scope isolation. See modules/foundation/deploy-identities.tf
# for full rationale.

variable "create_unified_deploy_identity" {
  type        = bool
  description = "Create the unified deploy UAMI (id-ghrunners-deploy) with FICs for all consumer repo+env combos. Should always be true in dev/test/prod once consolidation is in place."
  default     = false
}

variable "deploy_identity_location" {
  type        = string
  description = "Azure region for the unified deploy UAMI. Defaults to env location."
  default     = null
}

variable "github_secrets_pat" {
  type        = string
  description = "Fine-grained GitHub PAT scoped to eh-ciellos/ScaleInVmssFunction and eh-ciellos/ScaleOutVmssFunction with Secrets:Read+Write. Drives Option A (TF auto-syncs AZURE_CLIENT_ID env secrets to consumer repos). When empty, env secrets are NOT TF-managed."
  sensitive   = true
  default     = ""
}

variable "github_image_builder_pat" {
  type        = string
  description = "Fine-grained GitHub PAT scoped to gitspacecadet/vm-runner-image (Packer image-build repo) with Secrets:Read+Write. Drives the repo-level AZURE_CLIENT_ID / AZURE_SUBSCRIPTION_ID / AZURE_TENANT_ID auto-sync that closes the 2026-05-22 build-failure-after-sub-switch class. When empty, the vm-runner-image secrets are NOT TF-managed. Distinct from github_secrets_pat because vm-runner-image lives in a different GH org (gitspacecadet vs eh-ciellos) and a least-privilege PAT shouldn't span both orgs."
  sensitive   = true
  default     = ""
}

variable "create_image_builder_identity" {
  type        = bool
  description = "Create id-ghrunners-image-builder UAMI + its OIDC FIC (environment:image-build on gitspacecadet/vm-runner-image) + sub-wide Contributor role assignment. When true, vm-runner-image migrates from legacy SP+client-secret auth to OIDC. Pairs with var.github_image_builder_pat to push AZURE_CLIENT_ID/SUBSCRIPTION_ID/TENANT_ID secrets to the consumer repo."
  default     = false
}

# -----------------------------------------------------------------------------
# Phase 2B — ScaleOut Webhook function app
# -----------------------------------------------------------------------------

variable "deploy_scaleout_webhook_app" {
  type        = bool
  description = "Provision the dedicated webhook-handler function app (Arch B Phase 2B). Shares plan/storage/runtime UAMI with the queue processor; no worker cap."
  default     = false
}

# -----------------------------------------------------------------------------
# Phase 5 — ScaleIn reconciliation timer (drift detection vs GitHub runners API)
# -----------------------------------------------------------------------------
# ScaleIn's ProcVmssReconciliation timer cross-references VmssScaleAvailable
# and VmssScaleTracking against GitHub's runners API every N minutes (default
# 15 min) and logs drift. RECONCILE_AUTOFIX=false initially (read-only); flip
# after observation window to enable auto-cleanup.
#
# Activation lockstep — see .claude/Docs/Tracking/2026-04-26-phase5-activation-lockstep.md
# Step 2 (this TF apply) MUST precede ScaleIn's function.json edit.

variable "runner_scope" {
  type        = string
  description = "Single-string scope value: '<owner>/<repo>' for repo-scoped reconciliation, '<org>' (no slash) for org-scoped. Today's prod: 'gitspacecadet'. ScaleIn's reconciliation timer detects the form via slash presence."
  default     = ""
}

variable "reconcile_timer_schedule" {
  type        = string
  description = "Cron schedule for ScaleIn's ProcVmssReconciliation timer. Default fires every 15 minutes."
  default     = "0 */15 * * * *"
}

variable "reconcile_autofix" {
  type        = bool
  description = "If true, the reconciliation timer auto-cleans drift it finds (deletes orphan rows, removes dead GH runners). False = read-only logging."
  default     = false
}

variable "reconcile_pending_ttl_minutes" {
  type        = number
  description = "Pending row age (minutes) past which reconciliation considers it abandoned and flags/cleans it."
  default     = 10
}

variable "reconcile_attr_ttl_minutes" {
  type        = number
  description = "Tracking row stuck at Status=pending_attribution age (minutes) past which reconciliation considers attribution failed."
  default     = 5
}

# -----------------------------------------------------------------------------
# RDP Access Configuration (Dev Only)
# -----------------------------------------------------------------------------

variable "enable_rdp_access_dev" {
  type        = bool
  description = "Enable RDP access for dev environment only (adds public IP and NAT rules)"
  default     = false
}
