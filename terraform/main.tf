# -----------------------------------------------------------------------------
# GitHub VMSS Runners - Main Configuration
# -----------------------------------------------------------------------------
# Consolidated root module that works with environment-specific tfvars
# Usage: terraform plan -var-file=environments/dev.tfvars
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Unique Suffix for Storage Account Names
# -----------------------------------------------------------------------------
# Use a deterministic suffix derived from subscription ID to ensure consistency
# across deployments. This prevents storage account name changes on re-apply.
# The substr takes chars 0-3 from the subscription ID (after removing hyphens).

locals {
  # Generate deterministic suffix from subscription ID for storage account uniqueness
  # This ensures the same suffix is used across all deployments to the same subscription
  unique_suffix = substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 4)
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

# Note: Import block moved to imports.tf for centralized import management

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.app}-${var.environment}-${var.region}"
  location = var.location
  tags     = local.merged_tags
}

# -----------------------------------------------------------------------------
# Local Values - Configuration Merging
# -----------------------------------------------------------------------------

locals {
  # Merge user-provided tags with defaults
  merged_tags = merge(
    {
      Environment = title(var.environment)
      Project     = "GitHubRunners"
      ManagedBy   = "Terraform"
      Repository  = "gh-vmss-iac"
    },
    var.tags
  )

  # VMSS Configuration - merge defaults with environment-specific values
  vmss_config = {
    vm_size                      = coalesce(var.vmss_vm_size, local.default_vmss_config.vm_size)
    min_capacity                 = coalesce(var.vmss_min_capacity, local.default_vmss_config.min_capacity)
    max_capacity                 = coalesce(var.vmss_max_capacity, local.default_vmss_config.max_capacity)
    initial_capacity             = coalesce(var.vmss_initial_capacity, local.default_vmss_config.initial_capacity)
    admin_username               = coalesce(var.vmss_admin_username, local.default_vmss_config.admin_username)
    os_disk_size_gb              = local.default_vmss_config.os_disk_size_gb
    os_disk_storage_account_type = coalesce(var.os_disk_storage_account_type, local.default_vmss_config.os_disk_storage_account_type)
  }

  # Networking Configuration
  networking_config = {
    vnet_address_prefix   = coalesce(var.vnet_address_prefix, local.default_networking_config.vnet_address_prefix)
    subnet_address_prefix = coalesce(var.subnet_address_prefix, local.default_networking_config.subnet_address_prefix)
    lb_private_ip         = local.default_networking_config.lb_private_ip
  }

  # Storage Configuration - merge defaults with environment-specific values
  storage_config = {
    account_tier             = local.default_storage_config.account_tier
    account_replication_type = coalesce(var.storage_replication_type, local.default_storage_config.account_replication_type)
    account_kind             = local.default_storage_config.account_kind
    access_tier              = local.default_storage_config.access_tier
    min_tls_version          = local.default_storage_config.min_tls_version
  }

  # Compute Gallery Configuration
  gallery_config = {
    os_type            = local.default_gallery_config.os_type
    os_state           = local.default_gallery_config.os_state
    hyper_v_generation = coalesce(var.hyper_v_generation, local.default_gallery_config.hyper_v_generation)
    architecture       = local.default_gallery_config.architecture
    image_publisher    = local.default_gallery_config.image_publisher
    image_offer        = local.default_gallery_config.image_offer
    image_sku          = coalesce(var.image_sku, local.default_gallery_config.image_sku)
  }

  # Function App Configuration
  function_config = local.default_function_config

  # Log Analytics Configuration
  log_analytics_config = {
    sku               = local.default_log_analytics_config.sku
    retention_in_days = coalesce(var.log_analytics_retention_days, local.default_log_analytics_config.retention_in_days)
    daily_quota_gb    = local.default_log_analytics_config.daily_quota_gb
  }

  # Identity Strategy - passed from tfvars (using different name to avoid conflict with defaults.tf)
  selected_identity_strategy = var.identity_strategy

  # Key Vault Configuration - environment-aware
  key_vault_config = {
    soft_delete_retention_days = var.environment == "prod" ? 90 : 30
    purge_protection_enabled   = var.environment == "prod" ? true : false
    network_default_action     = "Allow"
    allowed_ip_ranges          = []
  }

  # RDP Access Configuration - dev environment only when explicitly requested
  enable_rdp = var.environment == "dev" && var.enable_rdp_access_dev

  # Queue-based webhook scaling — fixed names from defaults
  scaling_queue_names = local.default_scaling_queue_names
  scaling_table_names = local.default_scaling_table_names

  # Cleanup timer schedule
  cleanup_timer_schedule = local.default_cleanup_timer_schedule

  # NSG Rules - conditionally merge RDP rule for dev environment
  nsg_rules = local.enable_rdp ? concat(
    local.default_nsg_rules,
    [local.default_dev_rdp_nsg_rule]
  ) : local.default_nsg_rules
}

# -----------------------------------------------------------------------------
# Shared Module - Resource Naming
# -----------------------------------------------------------------------------

module "shared" {
  source = "./modules/shared"

  app           = var.app
  environment   = var.environment
  region        = var.region
  unique_suffix = local.unique_suffix
}

# -----------------------------------------------------------------------------
# Foundation Module
# -----------------------------------------------------------------------------

module "foundation" {
  source = "./modules/foundation"

  app                 = var.app
  environment         = var.environment
  region              = var.region
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.merged_tags
  unique_suffix       = local.unique_suffix

  resource_names       = module.shared.resource_names
  identity_strategy    = local.selected_identity_strategy
  networking_config    = local.networking_config
  nsg_rules            = local.nsg_rules
  gallery_config       = local.gallery_config
  storage_config       = local.storage_config
  log_analytics_config = local.log_analytics_config

  # Key Vault configuration for GitHub secrets
  key_vault_config           = local.key_vault_config
  github_private_key         = var.github_private_key
  github_pat                 = var.github_pat
  log_analytics_workspace_id = null # Will be populated after log analytics is created

  # Queue-based webhook scaling
  scaling_queue_names = local.scaling_queue_names
  scaling_table_names = local.scaling_table_names

  # RDP Access (dev only)
  enable_rdp_access = local.enable_rdp

  # Unified deploy UAMI: 1 UAMI + N FICs replaces the prior per-app UAMIs.
  # All consumer repos see the same AZURE_CLIENT_ID, pushed to GH env secrets
  # by the github provider in deploy-identities.tf when github_secrets_pat is set.
  create_unified_deploy_identity = var.create_unified_deploy_identity
  deploy_identity_location       = var.deploy_identity_location
  github_secrets_pat             = var.github_secrets_pat

  # Image-builder UAMI: separate from id-ghrunners-deploy. Sub-wide Contributor
  # for Packer. FIC subject is repo:gitspacecadet/vm-runner-image:environment:image-build.
  # Secrets pushed at repo level (not env-scoped) via the github.image_builder_scope
  # alias in providers.tf. See FromVmImageAgent/21.
  create_image_builder_identity = var.create_image_builder_identity
}

# -----------------------------------------------------------------------------
# Runtime Module
# -----------------------------------------------------------------------------

module "runtime" {
  source = "./modules/runtime"

  app                 = var.app
  environment         = var.environment
  region              = var.region
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  subscription_id     = data.azurerm_client_config.current.subscription_id
  tags                = local.merged_tags

  resource_names   = module.shared.resource_names
  deploy_vmss      = var.deploy_vmss
  deploy_functions = var.deploy_functions

  # Foundation references
  subnet_id                  = module.foundation.subnet_id
  lb_backend_pool_id         = module.foundation.lb_backend_pool_id
  log_analytics_id           = module.foundation.log_analytics_id
  log_analytics_workspace_id = module.foundation.log_analytics_workspace_id
  gallery_name               = module.foundation.gallery_name
  image_definition_name      = module.foundation.image_definition_name
  image_version              = var.image_version
  storage_scaleout_id        = module.foundation.storage_scaleout_id
  storage_scaleout_name      = module.foundation.storage_scaleout_name
  storage_scalein_id         = module.foundation.storage_scalein_id
  storage_scalein_name       = module.foundation.storage_scalein_name

  # Identity references
  vmss_identity_id               = module.foundation.vmss_identity_id
  vmss_identity_principal_id     = module.foundation.vmss_identity_principal_id
  scaleout_identity_id           = module.foundation.scaleout_identity_id
  scaleout_identity_principal_id = module.foundation.scaleout_identity_principal_id
  scalein_identity_id            = module.foundation.scalein_identity_id
  scalein_identity_principal_id  = module.foundation.scalein_identity_principal_id
  managed_identity_client_id     = module.foundation.managed_identity_client_id

  # Role assignment control flags (based on identity strategy, known at plan time)
  # RG-scoped roles: only create once per principal to avoid "RoleAssignmentExists" errors.
  # When using shared identity, all RG-scoped roles are created via scaleout flag only.
  create_vmss_role_assignments     = local.selected_identity_strategy.create_vmss_identity && !local.selected_identity_strategy.use_shared_identity
  create_scaleout_role_assignments = local.selected_identity_strategy.create_scaleout_identity || local.selected_identity_strategy.use_shared_identity
  create_scalein_role_assignments  = local.selected_identity_strategy.create_scalein_identity && !local.selected_identity_strategy.use_shared_identity

  # Storage-scoped roles for ScaleIn: these target storage_scalein_id (different scope from
  # ScaleOut's storage_scaleout_id), so they are NEVER duplicates and must always be created
  # when a ScaleIn function exists — regardless of identity strategy.
  create_scalein_storage_role_assignments = local.selected_identity_strategy.use_shared_identity || local.selected_identity_strategy.create_scalein_identity

  # VMSS configuration
  vmss_config               = local.vmss_config
  vmss_admin_password       = var.vmss_admin_password
  vmss_computer_name_prefix = local.default_vmss_computer_name_prefix[var.environment]

  # Function configuration
  function_config = local.function_config

  # GitHub configuration
  github_auth_strategy   = var.github_auth_strategy
  github_app_id          = var.github_app_id
  github_installation_id = var.github_installation_id
  github_private_key     = var.github_private_key
  github_pat             = var.github_pat
  github_organization    = var.github_organization

  # Key Vault references for GitHub secrets
  key_vault_id                  = module.foundation.key_vault_id
  github_private_key_secret_uri = module.foundation.github_private_key_secret_uri
  github_pat_secret_uri         = module.foundation.github_pat_secret_uri

  # Queue-based webhook scaling
  scaleout_queue_name    = module.foundation.scaleout_queue_name
  scalein_queue_name     = module.foundation.scalein_queue_name
  table_available_name   = module.foundation.table_available_name
  table_tracking_name    = module.foundation.table_tracking_name
  cleanup_timer_schedule = local.cleanup_timer_schedule

  # VMSS runner registration extension
  runner_script_url = module.foundation.runner_script_url

  # RDP Access (dev only)
  lb_nat_pool_id = local.enable_rdp ? module.foundation.lb_nat_pool_id : null

  # ScaleIn function — warm-pool cleanup tunables
  pool_ttl_minutes    = var.pool_ttl_minutes
  pool_cleanup_dryrun = var.pool_cleanup_dryrun

  # ScaleOut function — optional cross-worker serialization cap
  scaleout_max_scale_out_workers = var.scaleout_max_scale_out_workers

  # Unified deploy UAMI principal (null when create_unified_deploy_identity=false).
  # Single principal grants Website Contributor on every function app it deploys.
  deploy_identity_principal_id           = module.foundation.deploy_identity_principal_id
  create_unified_deploy_role_assignments = var.create_unified_deploy_identity

  # Phase 2B — ScaleOut webhook function app provisioning toggle (independent of deploy UAMI)
  deploy_scaleout_webhook_app = var.deploy_scaleout_webhook_app

  # Phase 5 — ScaleIn reconciliation timer (drift detection vs GitHub runners API)
  runner_scope                  = var.runner_scope
  reconcile_timer_schedule      = var.reconcile_timer_schedule
  reconcile_autofix             = var.reconcile_autofix
  reconcile_pending_ttl_minutes = var.reconcile_pending_ttl_minutes
  reconcile_attr_ttl_minutes    = var.reconcile_attr_ttl_minutes

  depends_on = [module.foundation]
}
