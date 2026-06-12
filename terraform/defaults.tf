# -----------------------------------------------------------------------------
# Centralized Defaults - GitHub VMSS Runners Infrastructure
# Equivalent to parameters/default.bicep with @export()
# -----------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Default Tags
  # ---------------------------------------------------------------------------
  default_tags = {
    Project    = "GitHubRunners"
    ManagedBy  = "Terraform"
    Repository = "gh-vmss-iac"
  }

  # ---------------------------------------------------------------------------
  # VMSS Configuration Defaults
  # ---------------------------------------------------------------------------
  default_vmss_config = {
    vm_size                      = "Standard_B4ms"
    min_capacity                 = 0
    max_capacity                 = 10
    initial_capacity             = 0
    admin_username               = "azureadmin"
    os_disk_size_gb              = 256
    os_disk_storage_account_type = "Standard_LRS"
  }

  # Environment-specific VMSS overrides
  vmss_env_overrides = {
    dev = {
      vm_size                      = "Standard_B4ms"
      max_capacity                 = 10
      os_disk_storage_account_type = "Standard_LRS"
    }
    test = {
      vm_size                      = "Standard_B4ms"
      max_capacity                 = 10
      os_disk_storage_account_type = "StandardSSD_LRS"
    }
    prod = {
      vm_size                      = "Standard_D4s_v3"
      max_capacity                 = 20
      os_disk_storage_account_type = "Premium_LRS"
    }
  }

  # VMSS computer name prefix (max 9 chars for Windows)
  default_vmss_computer_name_prefix = {
    dev  = "vmss-dev"  # 8 chars
    test = "vmss-test" # 9 chars
    prod = "vmss-prd"  # 8 chars
  }

  # ---------------------------------------------------------------------------
  # Networking Configuration Defaults
  # ---------------------------------------------------------------------------
  default_networking_config = {
    vnet_address_prefix   = "10.0.0.0/16"
    subnet_address_prefix = "10.0.0.0/24"
    lb_private_ip         = "10.0.0.10"
  }

  # ---------------------------------------------------------------------------
  # Storage Configuration Defaults
  # ---------------------------------------------------------------------------
  default_storage_config = {
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"
    access_tier              = "Hot"
    min_tls_version          = "TLS1_2"
  }

  # Environment-specific storage overrides
  storage_env_overrides = {
    dev = {
      account_replication_type = "LRS"
    }
    test = {
      account_replication_type = "LRS"
    }
    prod = {
      account_replication_type = "ZRS"
    }
  }

  # ---------------------------------------------------------------------------
  # Compute Gallery Configuration Defaults
  # ---------------------------------------------------------------------------
  default_gallery_config = {
    os_type            = "Windows"
    os_state           = "Generalized"
    hyper_v_generation = "V1"
    architecture       = "x64"
    image_publisher    = "MicrosoftWindowsServer"
    image_offer        = "WindowsServer"
    image_sku          = "2022-datacenter-g2"
  }

  # Environment-specific gallery overrides
  gallery_env_overrides = {
    dev = {
      hyper_v_generation = "V1"
    }
    test = {
      hyper_v_generation = "V1"
    }
    prod = {
      hyper_v_generation = "V2"
    }
  }

  # ---------------------------------------------------------------------------
  # Function App Configuration Defaults
  # ---------------------------------------------------------------------------
  default_function_config = {
    runtime_version    = "~4"
    powershell_version = "7.4"
    os_type            = "Windows"
    sku_name           = "Y1" # Consumption plan
  }

  # ---------------------------------------------------------------------------
  # Queue-Based Webhook Scaling — Fixed Resource Names
  # ---------------------------------------------------------------------------
  # These names are part of the Valery architecture contract and are fixed
  # across environments. Function code references them via app_settings env vars.
  default_scaling_queue_names = {
    scaleout = "vmss-scale-requests"
    scalein  = "vmss-scale-in-requests"
  }

  default_scaling_table_names = {
    available          = "VmssScaleAvailable"
    tracking           = "VmssScaleTracking"
    pending            = "VmssScalePending"
    reconcile_tracking = "VmssReconcileTracking"
  }

  # Cleanup timer: every 5 minutes (replaces the old 15-min scale-in timer)
  default_cleanup_timer_schedule = "0 */5 * * * *"

  # ---------------------------------------------------------------------------
  # Log Analytics Configuration Defaults
  # ---------------------------------------------------------------------------
  default_log_analytics_config = {
    sku               = "PerGB2018"
    retention_in_days = 30
    daily_quota_gb    = -1 # Unlimited
  }

  # Environment-specific log analytics overrides
  log_analytics_env_overrides = {
    dev = {
      retention_in_days = 30
    }
    test = {
      retention_in_days = 30
    }
    prod = {
      retention_in_days = 730 # Max retention for compliance
    }
  }

  # ---------------------------------------------------------------------------
  # Managed Identity Strategy by Environment (reference — NOT consumed)
  # ---------------------------------------------------------------------------
  # Actual per-env values come from environments/<env>.tfvars and are validated
  # against the rule in variables.tf: when use_shared_identity=true, all
  # create_*_identity flags MUST be false.
  #
  # dev:  1 shared user-assigned MI (kept simple)
  # test: TBD — planned as 3 dedicated MIs (Option A) on first deploy
  # prod: 3 separate user-assigned MIs (VMSS, ScaleOut, ScaleIn)
  identity_strategy = {
    dev = {
      create_vmss_identity     = false
      create_scaleout_identity = false
      create_scalein_identity  = false
      use_shared_identity      = true
    }
    test = {
      create_vmss_identity     = true
      create_scaleout_identity = true
      create_scalein_identity  = true
      use_shared_identity      = false
    }
    prod = {
      create_vmss_identity     = true
      create_scaleout_identity = true
      create_scalein_identity  = true
      use_shared_identity      = false
    }
  }

  # ---------------------------------------------------------------------------
  # NSG Rules Defaults
  # ---------------------------------------------------------------------------
  default_nsg_rules = [
    {
      name                       = "AllowHTTPSOutbound"
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    },
    {
      name                       = "AllowHTTPOutbound"
      priority                   = 110
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    },
    {
      name                       = "AllowDNSOutbound"
      priority                   = 120
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "53"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
  ]

  # ---------------------------------------------------------------------------
  # Dev-only RDP NSG Rule (Conditionally Applied)
  # ---------------------------------------------------------------------------
  default_dev_rdp_nsg_rule = {
    name                       = "AllowRDPInbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*" # TODO: Restrict to specific IP ranges for production use
    destination_address_prefix = "*"
  }
}
