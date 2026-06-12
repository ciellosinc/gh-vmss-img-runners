# -----------------------------------------------------------------------------
# Input Validation - GitHub VMSS Runners Infrastructure
# -----------------------------------------------------------------------------
# Cross-variable validation using terraform_data resources with preconditions
# This provides early failure with clear error messages
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# GitHub Authentication Validation
# -----------------------------------------------------------------------------
# Ensures required credentials are provided based on the selected auth strategy:
# - GitHubApp: requires github_app_id, github_installation_id, github_private_key
# - PAT: requires github_pat
# -----------------------------------------------------------------------------

resource "terraform_data" "github_auth_validation" {
  lifecycle {
    precondition {
      condition = (
        var.github_auth_strategy == "GitHubApp" ? (
          var.github_app_id != "" &&
          var.github_installation_id != "" &&
          var.github_private_key != ""
        ) : true
      )
      error_message = <<-EOT
        GitHub App authentication requires all of the following variables to be set:
        - github_app_id (currently ${var.github_app_id == "" ? "EMPTY" : "set"})
        - github_installation_id (currently ${var.github_installation_id == "" ? "EMPTY" : "set"})
        - github_private_key (currently ${var.github_private_key == "" ? "EMPTY" : "set"})

        Either provide all required GitHub App credentials or switch to PAT authentication
        by setting github_auth_strategy = "PAT" and providing github_pat.
      EOT
    }

    precondition {
      condition = (
        var.github_auth_strategy == "PAT" ? (
          var.github_pat != ""
        ) : true
      )
      error_message = <<-EOT
        PAT authentication requires the github_pat variable to be set.

        Either provide a valid GitHub Personal Access Token or switch to GitHub App
        authentication by setting github_auth_strategy = "GitHubApp" and providing
        the required credentials (github_app_id, github_installation_id, github_private_key).
      EOT
    }

    precondition {
      condition = (
        var.github_organization != "" || !var.deploy_functions
      )
      error_message = <<-EOT
        The github_organization variable must be set when deploying Function Apps.
        This is required for GitHub runner registration.
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# VMSS Configuration Validation
# -----------------------------------------------------------------------------
# Ensures VMSS capacity settings are consistent
# -----------------------------------------------------------------------------

resource "terraform_data" "vmss_config_validation" {
  lifecycle {
    precondition {
      condition = (
        !var.deploy_vmss ||
        (coalesce(var.vmss_min_capacity, 0) <= coalesce(var.vmss_max_capacity, 10))
      )
      error_message = <<-EOT
        VMSS minimum capacity cannot exceed maximum capacity.
        - vmss_min_capacity: ${coalesce(var.vmss_min_capacity, 0)}
        - vmss_max_capacity: ${coalesce(var.vmss_max_capacity, 10)}
      EOT
    }

    precondition {
      condition = (
        !var.deploy_vmss ||
        (coalesce(var.vmss_initial_capacity, 0) <= coalesce(var.vmss_max_capacity, 10))
      )
      error_message = <<-EOT
        VMSS initial capacity cannot exceed maximum capacity.
        - vmss_initial_capacity: ${coalesce(var.vmss_initial_capacity, 0)}
        - vmss_max_capacity: ${coalesce(var.vmss_max_capacity, 10)}
      EOT
    }

    precondition {
      condition = (
        !var.deploy_vmss ||
        (coalesce(var.vmss_initial_capacity, 0) >= coalesce(var.vmss_min_capacity, 0))
      )
      error_message = <<-EOT
        VMSS initial capacity cannot be less than minimum capacity.
        - vmss_initial_capacity: ${coalesce(var.vmss_initial_capacity, 0)}
        - vmss_min_capacity: ${coalesce(var.vmss_min_capacity, 0)}
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# Environment-Specific Validation
# -----------------------------------------------------------------------------
# Ensures production environments have appropriate security settings
# -----------------------------------------------------------------------------

resource "terraform_data" "environment_validation" {
  lifecycle {
    precondition {
      condition = (
        var.environment != "prod" ||
        var.prevent_resource_group_deletion == true
      )
      error_message = <<-EOT
        Production environments should have resource group deletion prevention enabled.
        Set prevent_resource_group_deletion = true for production deployments.
      EOT
    }

    precondition {
      condition = (
        var.environment != "prod" ||
        !var.enable_rdp_access_dev
      )
      error_message = <<-EOT
        RDP access cannot be enabled in production environment for security reasons.
        RDP access is only allowed in dev and test environments.
        Set enable_rdp_access_dev = false for production deployments.
      EOT
    }
  }
}
