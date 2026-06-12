# -----------------------------------------------------------------------------
# Resource Naming Conventions - Shared Module
# Equivalent to shared.bicep generateResourceName functions
# -----------------------------------------------------------------------------

locals {
  # Resource type abbreviations (CAF naming conventions)
  resource_abbreviations = {
    compute_gallery        = "sig"
    image_definition       = "img"
    vmss                   = "vmss"
    managed_identity       = "id"
    virtual_network        = "vnet"
    subnet                 = "snet"
    network_security_group = "nsg"
    load_balancer          = "lb"
    public_ip              = "pip"
    storage_account        = "st"
    function_app           = "func"
    app_insights           = "appi"
    app_service_plan       = "asp"
    key_vault              = "kv"
    log_analytics          = "log"
    action_group           = "ag"
    alert                  = "alert"
  }

  # Standard naming format: {type}-{app}-{env}-{region}
  # With suffix: {type}-{suffix}-{app}-{env}-{region}
  name_format        = "%s-%s-%s-%s"
  name_format_suffix = "%s-%s-%s-%s-%s"

  # Generate all standard resource names
  resource_names = {
    # Resource Group
    resource_group = format(local.name_format, "rg", var.app, var.environment, var.region)

    # Managed Identities
    identity_vmss     = format(local.name_format_suffix, local.resource_abbreviations.managed_identity, "vmss", var.app, var.environment, var.region)
    identity_scaleout = format(local.name_format_suffix, local.resource_abbreviations.managed_identity, "func-scaleout", var.app, var.environment, var.region)
    identity_scalein  = format(local.name_format_suffix, local.resource_abbreviations.managed_identity, "func-scalein", var.app, var.environment, var.region)
    identity_shared   = format(local.name_format_suffix, local.resource_abbreviations.managed_identity, "shared", var.app, var.environment, var.region)

    # Networking
    vnet   = format(local.name_format, local.resource_abbreviations.virtual_network, var.app, var.environment, var.region)
    subnet = format(local.name_format_suffix, local.resource_abbreviations.subnet, "runners", var.app, var.environment, var.region)
    nsg    = format(local.name_format, local.resource_abbreviations.network_security_group, var.app, var.environment, var.region)
    lb     = format(local.name_format, local.resource_abbreviations.load_balancer, var.app, var.environment, var.region)
    pip    = format(local.name_format, local.resource_abbreviations.public_ip, var.app, var.environment, var.region)

    # Compute Gallery
    gallery          = replace(format("gh_runner_images_%s", var.environment), "-", "_")
    image_definition = var.environment == "prod" ? "2022-Datacenter-Gen2-Def" : "2022-Datacenter-Def"

    # VMSS
    vmss = format(local.name_format, local.resource_abbreviations.vmss, var.app, var.environment, var.region)

    # Storage Accounts (no hyphens, max 24 chars, lowercase)
    storage_scaleout = lower(substr(replace(format("st%s%sscaleout%s", var.app, var.environment, var.unique_suffix), "-", ""), 0, 24))
    storage_scalein  = lower(substr(replace(format("st%s%sscalein%s", var.app, var.environment, var.unique_suffix), "-", ""), 0, 24))

    # Function Apps (hostnames globally unique under azurewebsites.net)
    # Include unique_suffix so names don't collide with soft-deleted/preserved
    # apps from other subs (same pattern as KV).
    func_scaleout         = format("%s-%s-%s-%s-%s-%s", local.resource_abbreviations.function_app, "scaleout", var.app, var.environment, var.region, var.unique_suffix)
    func_scaleout_webhook = format("%s-%s-%s-%s-%s-%s", local.resource_abbreviations.function_app, "scaleout-webhook", var.app, var.environment, var.region, var.unique_suffix)
    func_scalein          = format("%s-%s-%s-%s-%s-%s", local.resource_abbreviations.function_app, "scalein", var.app, var.environment, var.region, var.unique_suffix)

    # App Service Plans
    asp_scaleout = format(local.name_format_suffix, local.resource_abbreviations.app_service_plan, "scaleout", var.app, var.environment, var.region)
    asp_scalein  = format(local.name_format_suffix, local.resource_abbreviations.app_service_plan, "scalein", var.app, var.environment, var.region)

    # Monitoring
    appi_scaleout = format(local.name_format_suffix, local.resource_abbreviations.app_insights, "scaleout", var.app, var.environment, var.region)
    appi_scalein  = format(local.name_format_suffix, local.resource_abbreviations.app_insights, "scalein", var.app, var.environment, var.region)
    log_analytics = format(local.name_format, local.resource_abbreviations.log_analytics, var.app, var.environment, var.region)

    # Key Vault (3-24 chars, alphanumeric + hyphens)
    # Include unique_suffix (from subscription ID) because KV names are globally reserved
    # by the soft-delete mechanism for ~30 days. Suffix keeps names unique per subscription.
    key_vault = substr(format("kv-%s-%s-%s-%s", var.app, var.environment, var.region, var.unique_suffix), 0, 24)
  }
}
