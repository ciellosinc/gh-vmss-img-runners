# -----------------------------------------------------------------------------
# Networking Resources - Foundation Module
# Creates VNet, Subnet, NSG, and Load Balancer
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Network Security Group
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "main" {
  name                = var.resource_names.nsg
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# NSG Rules
resource "azurerm_network_security_rule" "rules" {
  for_each = { for idx, rule in var.nsg_rules : rule.name => rule }

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = var.resource_names.vnet
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.networking_config.vnet_address_prefix]
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Subnet
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "runners" {
  name                 = var.resource_names.subnet
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.networking_config.subnet_address_prefix]
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "runners" {
  subnet_id                 = azurerm_subnet.runners.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# -----------------------------------------------------------------------------
# Public IP for Outbound Connectivity
# -----------------------------------------------------------------------------
# GitHub runners need OUTBOUND connectivity to GitHub API, package repos, etc.
# Using LB Outbound Rules with a Public IP provides:
# - Predictable egress IP (for IP allowlisting if needed)
# - Configurable SNAT ports
# - Cost-effective (~$3.65/mo vs ~$32/mo for NAT Gateway)

resource "azurerm_public_ip" "outbound" {
  name                = var.resource_names.pip
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Public IP for inbound RDP access (dev environment only)
resource "azurerm_public_ip" "inbound" {
  count = var.enable_rdp_access ? 1 : 0

  name                = "${var.resource_names.pip}-inbound"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(var.tags, { Purpose = "RDP-Access-Dev" })

  # DNS labels under *.cloudapp.azure.com are globally unique. Include unique_suffix
  # so names don't collide with soft-deleted records from other subs.
  domain_name_label = "${var.resource_names.lb}-rdp-${var.unique_suffix}"
}

# -----------------------------------------------------------------------------
# Load Balancer (Standard SKU for Outbound Rules)
# -----------------------------------------------------------------------------

resource "azurerm_lb" "main" {
  name                = var.resource_names.lb
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  # Public frontend for outbound SNAT
  # Note: Standard LB cannot mix public and private frontends
  frontend_ip_configuration {
    name                 = "outbound"
    public_ip_address_id = azurerm_public_ip.outbound.id
  }

  # Inbound frontend for RDP (dev only)
  dynamic "frontend_ip_configuration" {
    for_each = var.enable_rdp_access ? [1] : []
    content {
      name                 = "inbound"
      public_ip_address_id = azurerm_public_ip.inbound[0].id
    }
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "main" {
  name            = "vmss-backend-pool"
  loadbalancer_id = azurerm_lb.main.id
}

# Health Probe
resource "azurerm_lb_probe" "main" {
  name                = "tcp-probe"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Tcp"
  port                = 443
  interval_in_seconds = 5
  number_of_probes    = 2
}

# -----------------------------------------------------------------------------
# Outbound Rule for SNAT
# -----------------------------------------------------------------------------
# Provides outbound internet connectivity for VMSS instances via the public IP.
# SNAT ports are allocated per instance (1024 ports each with 10 max instances).

resource "azurerm_lb_outbound_rule" "main" {
  name                    = "outbound-rule"
  loadbalancer_id         = azurerm_lb.main.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id

  frontend_ip_configuration {
    name = "outbound"
  }

  # Allocate SNAT ports per instance
  # With 10240 ports and max 10 instances = 1024 ports/instance
  allocated_outbound_ports = 1024
  idle_timeout_in_minutes  = 4
}

# -----------------------------------------------------------------------------
# Inbound NAT Pool for RDP Access (Dev Only)
# -----------------------------------------------------------------------------
# Maps public ports 50000-50099 to RDP port 3389 on VMSS instances
# Supports up to 100 instances
# Instance 0 = port 50000, Instance 1 = port 50001, etc.

resource "azurerm_lb_nat_pool" "rdp" {
  count = var.enable_rdp_access ? 1 : 0

  name                           = "rdp-nat-pool"
  resource_group_name            = var.resource_group_name
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50099
  backend_port                   = 3389
  frontend_ip_configuration_name = "inbound"

  depends_on = [azurerm_lb.main]
}
