# -----------------------------------------------------------------------------
# Foundation Module - Main Orchestration
# Deploys: Managed Identities, Networking, Compute Gallery, Storage, Log Analytics
# -----------------------------------------------------------------------------

# This module creates the foundation infrastructure required before runtime
# deployment. All resources are created in a single resource group.
#
# Deployment order (handled by Terraform dependencies):
# 1. Managed Identities (0-3 based on environment)
# 2. Network Security Group
# 3. Virtual Network + Subnet
# 4. Load Balancer
# 5. Compute Gallery + Image Definition
# 6. Storage Accounts (2x)
# 7. Log Analytics Workspace
#
# Note: Resources are defined in separate files for maintainability:
# - managed-identity.tf
# - networking.tf
# - compute-gallery.tf
# - storage.tf
# - log-analytics.tf
