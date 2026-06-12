# -----------------------------------------------------------------------------
# Compute Gallery - Foundation Module
# Creates Shared Image Gallery and Image Definition
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Shared Image Gallery
# -----------------------------------------------------------------------------

resource "azurerm_shared_image_gallery" "main" {
  name                = var.resource_names.gallery
  location            = var.location
  resource_group_name = var.resource_group_name
  description         = "Shared image gallery for GitHub runner images"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Image Definition
# -----------------------------------------------------------------------------

resource "azurerm_shared_image" "runner" {
  name                = var.resource_names.image_definition
  gallery_name        = azurerm_shared_image_gallery.main.name
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type            = var.gallery_config.os_type
  hyper_v_generation = var.gallery_config.hyper_v_generation
  architecture       = var.gallery_config.architecture

  identifier {
    publisher = var.gallery_config.image_publisher
    offer     = var.gallery_config.image_offer
    sku       = var.gallery_config.image_sku
  }

  tags = var.tags
}
