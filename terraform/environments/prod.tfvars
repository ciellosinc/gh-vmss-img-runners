# -----------------------------------------------------------------------------
# Production Environment Configuration
# -----------------------------------------------------------------------------
# Usage: terraform plan -var-file=environments/prod.tfvars
# Backend: terraform init -backend-config=environments/prod/backend.tf
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Environment Identifiers
# -----------------------------------------------------------------------------

environment = "prod"
app         = "ghrunners"
region      = "cus"
location    = "centralus"

# -----------------------------------------------------------------------------
# Deployment Control
# -----------------------------------------------------------------------------

deploy_vmss      = true
deploy_functions = true

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

# Prevent accidental resource group deletion in production
prevent_resource_group_deletion = true

# -----------------------------------------------------------------------------
# Additional Tags - Production
# -----------------------------------------------------------------------------

tags = {
  CostCenter = "Infrastructure"
}

# -----------------------------------------------------------------------------
# VMSS Configuration - Production
# -----------------------------------------------------------------------------
# Production uses dedicated VMs with premium storage for consistent performance

vmss_vm_size                 = "Standard_D4s_v3"
vmss_max_capacity            = 20
os_disk_storage_account_type = "Premium_LRS"

# -----------------------------------------------------------------------------
# Storage Configuration - Production
# -----------------------------------------------------------------------------
# Zone-redundant storage for high availability

storage_replication_type = "ZRS"

# -----------------------------------------------------------------------------
# Compute Gallery Configuration - Production
# -----------------------------------------------------------------------------
# Gen2 VMs for production (better performance, security features)

hyper_v_generation = "V2"
image_sku          = "2022-datacenter-azure-edition"

# -----------------------------------------------------------------------------
# Log Analytics Configuration - Production
# -----------------------------------------------------------------------------
# Maximum retention for compliance (730 days = 2 years)

log_analytics_retention_days = 730

# -----------------------------------------------------------------------------
# Identity Strategy - Production
# -----------------------------------------------------------------------------
# Production: 3 separate user-assigned managed identities (least privilege)

identity_strategy = {
  create_vmss_identity     = true
  create_scaleout_identity = true
  create_scalein_identity  = true
  use_shared_identity      = false
}

# -----------------------------------------------------------------------------
# Image Version
# -----------------------------------------------------------------------------

image_version = "1.0.0"

# -----------------------------------------------------------------------------
# GitHub Configuration
# -----------------------------------------------------------------------------

github_auth_strategy = "GitHubApp"
# github_app_id          = ""      # Provide via -var or TF_VAR_
# github_installation_id = ""      # Provide via -var or TF_VAR_
# github_organization    = ""      # Provide via -var or TF_VAR_

# -----------------------------------------------------------------------------
# Sensitive Values - Pass via environment variables or -var flag
# -----------------------------------------------------------------------------
# vmss_admin_password    = ""      # TF_VAR_vmss_admin_password
# github_private_key     = ""      # TF_VAR_github_private_key
# github_pat             = ""      # TF_VAR_github_pat
