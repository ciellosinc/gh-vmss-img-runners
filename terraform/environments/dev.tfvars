# -----------------------------------------------------------------------------
# Development Environment Configuration
# -----------------------------------------------------------------------------
# Usage: terraform plan -var-file=environments/dev.tfvars
# Backend: terraform init -backend-config=environments/dev/backend.tf
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Environment Identifiers
# -----------------------------------------------------------------------------

environment = "dev"
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

# Allow resource group deletion in dev (for easy cleanup)
prevent_resource_group_deletion = false

# -----------------------------------------------------------------------------
# VMSS Configuration - Development
# -----------------------------------------------------------------------------
# Dev uses burstable VMs and standard storage for cost efficiency

vmss_vm_size                 = "Standard_B4ms"
vmss_min_capacity            = 0
vmss_max_capacity            = 10
vmss_initial_capacity        = 0
os_disk_storage_account_type = "StandardSSD_LRS"

# -----------------------------------------------------------------------------
# Storage Configuration - Development
# -----------------------------------------------------------------------------
# LRS replication is sufficient for dev

storage_replication_type = "LRS"

# -----------------------------------------------------------------------------
# Compute Gallery Configuration - Development
# -----------------------------------------------------------------------------

hyper_v_generation = "V1"

# -----------------------------------------------------------------------------
# Log Analytics Configuration - Development
# -----------------------------------------------------------------------------
# 30-day retention for dev (minimum)

log_analytics_retention_days = 30

# -----------------------------------------------------------------------------
# Identity Strategy - Development
# -----------------------------------------------------------------------------
# Dev: 1 shared user-assigned MI covers VMSS + both Function Apps. The resolver
# in modules/foundation/managed-identity.tf picks the shared MI when
# use_shared_identity=true, so create_*_identity flags MUST all be false —
# otherwise the dedicated MI is created but never referenced (silent waste).
# Enforced by the identity_strategy validation block in variables.tf.

identity_strategy = {
  create_vmss_identity     = false
  create_scaleout_identity = false
  create_scalein_identity  = false
  use_shared_identity      = true
}

# -----------------------------------------------------------------------------
# Image Version
# -----------------------------------------------------------------------------

# "latest" = VMSS uses the newest non-excluded version in the gallery definition.
# Pin to a specific version (e.g. "28.46665.49267") only when you need reproducibility.
image_version = "latest"

# -----------------------------------------------------------------------------
# GitHub Configuration
# -----------------------------------------------------------------------------

github_auth_strategy = "PAT"
# github_organization    = ""      # Provide via TF_VAR_github_organization

# -----------------------------------------------------------------------------
# RDP Access Configuration - Development Only
# -----------------------------------------------------------------------------
# Enable RDP access for dev environment troubleshooting
# Allows connecting to VMSS instances via load balancer NAT rules

enable_rdp_access_dev = true

# -----------------------------------------------------------------------------
# Import Configuration (for existing resources from foundation deployment)
# -----------------------------------------------------------------------------
# These values are used to import existing Key Vault secrets into Terraform state.
# The version ID can be found in the Azure portal or from Terraform error messages.

import_kv_secret_pat_version = "03a4f00eae6645ac93b61bff861a7ee5"

# -----------------------------------------------------------------------------
# Function App — Warm Pool Cleanup (ScaleIn)
# -----------------------------------------------------------------------------
# Live mode confirmed working since 2026-04-23 (3 VMs/rows/tags reaped successfully).
pool_ttl_minutes    = 15
pool_cleanup_dryrun = false

# -----------------------------------------------------------------------------
# Function App — ScaleOut Worker Cap (REMOVED 2026-04-26)
# -----------------------------------------------------------------------------
# WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT was previously set to "1" here as
# defense against Bug 2 (VMSS-InstanceId sampling race). Phase 4B replaced
# that defense with self-attribution: VMs claim their own pending row at
# boot, so concurrent queue processing no longer races on instance sampling.
#
# IMPORTANT: empirical evidence from the 2026-04-26 burst test showed the
# cap setting did NOT actually serialize queue triggers on Y1 Consumption
# (3 messages processed within 4s of each other despite the setting being
# live). The setting was non-functional for our pattern.
#
# Cap removal SEQUENCED with ScaleOut's stale-capacity-read fix to avoid
# exposing a different race (parallel Update-AzVmss calls coalescing in
# ARM under concurrent capacity reads). See ScaleOut hand-off:
#   .claude/Docs/FromScaleoOutAgent/07-phase-4b-narrow-signoff-plus-3-hardening-asks-2026-04-26.md
# and tracking doc:
#   .claude/Docs/Tracking/2026-04-26-scaleout-worker-cap-non-functional.md
#
# Variable remains defined for test/prod opt-in if a future use case
# emerges. Default null = setting omitted from app_settings.
# scaleout_max_scale_out_workers = 1   # ← removed

# -----------------------------------------------------------------------------
# Unified Deploy UAMI — id-ghrunners-deploy (1 UAMI, multiple FICs)
# -----------------------------------------------------------------------------
# Replaces the prior pair (id-scalein-ghrunners-deploy + id-scaleout-webhook-
# ghrunners-deploy). One principal grants Website Contributor scoped per
# function app; multiple FICs federate each consumer repo's GH Actions to
# the same clientId, eliminating per-app stale-clientId failures.
#
# AZURE_CLIENT_ID is auto-pushed to consumer repos' production environments
# via the hashicorp/github provider when github_secrets_pat is set
# (TF_VAR_github_secrets_pat from GH_SECRETS_PAT repo secret in CI).
# See .claude/Docs/Tracking/2026-04-26-gh-env-secrets-for-deploy-uami.md
create_unified_deploy_identity = true
deploy_identity_location       = "centralus"

# -----------------------------------------------------------------------------
# Image Builder OIDC Migration (FromVmImageAgent/21, 2026-05-22)
# -----------------------------------------------------------------------------
# Enable in dev to retire vm-runner-image's legacy SP+client-secret auth.
# Creates id-ghrunners-image-builder UAMI + FIC for environment:image-build
# on gitspacecadet/vm-runner-image + sub-wide Contributor RA + 3 repo-level
# GH secrets (CLIENT_ID, SUB_ID, TENANT_ID). After apply, vm-image agent
# creates the GH environment, updates the workflow to OIDC, and retires
# AZURE_CLIENT_SECRET.
create_image_builder_identity = true

# -----------------------------------------------------------------------------
# Phase 5 — ScaleIn reconciliation timer
# -----------------------------------------------------------------------------
# PAT decision (project owner, 2026-04-26): Option A — reuse the existing
# github-pat KV secret. GITHUB_RECONCILE_TOKEN in scalein function app_settings
# is wired to the same secret URI as GITHUB_PAT in TF code. Future swap to a
# narrower-scope token is a one-line change in modules/runtime/function-app.tf.
#
# Activation lockstep: this apply must precede ScaleIn's function.json edit
# (which switches schedule from "0 0 0 1 1 *" to "%RECONCILE_TIMER_SCHEDULE%").
# See .claude/Docs/Tracking/2026-04-26-phase5-activation-lockstep.md.
runner_scope                  = "gitspacecadet"
reconcile_timer_schedule      = "0 */15 * * * *"
reconcile_autofix             = false
reconcile_pending_ttl_minutes = 10
reconcile_attr_ttl_minutes    = 5

# -----------------------------------------------------------------------------
# Phase 2B — ScaleOut Webhook Function App
# -----------------------------------------------------------------------------
# Splits the ScaleOut compute path. The new webhook app hosts only
# GhWebHookScaleOut and scales freely (no worker cap), enabling parallel pool
# claims under burst load. The existing scaleout app keeps the queue processor
# + the WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT=1 cap until Phase 4B is
# verified end-to-end and ScaleOut signs off.
# Webhook app's deploy UAMI is now part of the unified deploy identity (above)
# — no separate UAMI flag here.
# See .claude/Docs/FromScaleoOutAgent/02-arch-b-phase-2b-acks-and-asks-2026-04-25.md
deploy_scaleout_webhook_app = true

# -----------------------------------------------------------------------------
# Sensitive Values - Pass via environment variables or -var flag
# -----------------------------------------------------------------------------
# vmss_admin_password    = ""      # TF_VAR_vmss_admin_password
# github_private_key     = ""      # TF_VAR_github_private_key
# github_pat             = ""      # TF_VAR_github_pat
