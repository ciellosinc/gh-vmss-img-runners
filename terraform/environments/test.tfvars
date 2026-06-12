# -----------------------------------------------------------------------------
# Test Environment Configuration
# -----------------------------------------------------------------------------
# Usage: terraform plan -var-file=environments/test.tfvars
# Backend: terraform init -backend-config=environments/test/backend.tf
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Environment Identifiers
# -----------------------------------------------------------------------------

environment = "test"
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

# Allow resource group deletion in test (for test automation)
prevent_resource_group_deletion = false

# -----------------------------------------------------------------------------
# VMSS Configuration - Test
# -----------------------------------------------------------------------------
# Test uses burstable VMs with SSD storage for better test performance

vmss_vm_size                 = "Standard_B4ms"
vmss_max_capacity            = 10
os_disk_storage_account_type = "StandardSSD_LRS"

# -----------------------------------------------------------------------------
# Storage Configuration - Test
# -----------------------------------------------------------------------------
# LRS replication is sufficient for test

storage_replication_type = "LRS"

# -----------------------------------------------------------------------------
# Compute Gallery Configuration - Test
# -----------------------------------------------------------------------------

hyper_v_generation = "V1"

# -----------------------------------------------------------------------------
# Log Analytics Configuration - Test
# -----------------------------------------------------------------------------
# 30-day retention for test

log_analytics_retention_days = 30

# -----------------------------------------------------------------------------
# Identity Strategy - Test
# -----------------------------------------------------------------------------
# Test: 1 shared user-assigned managed identity

identity_strategy = {
  create_vmss_identity     = true
  create_scaleout_identity = false
  create_scalein_identity  = false
  use_shared_identity      = true
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
