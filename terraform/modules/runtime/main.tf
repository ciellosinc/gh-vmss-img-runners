# -----------------------------------------------------------------------------
# Runtime Module - Main Orchestration
# Deploys: Application Insights, Role Assignments, VMSS, Function Apps
# -----------------------------------------------------------------------------

# This module creates the runtime infrastructure that depends on foundation.
# It references existing foundation resources (identities, storage, networking).
#
# Deployment order (handled by Terraform dependencies):
# 1. Application Insights (2x - ScaleOut, ScaleIn)
# 2. Role Assignments (18 RBAC assignments)
# 3. Virtual Machine Scale Set (depends on role assignments)
# 4. Function Apps (2x - depends on role assignments)
#
# Note: Resources are defined in separate files for maintainability:
# - monitoring.tf
# - role-assignments.tf
# - vmss.tf
# - function-app.tf
