# -----------------------------------------------------------------------------
# Deploy Identity (UNIFIED) — Function App CI/CD via GitHub Actions OIDC
# -----------------------------------------------------------------------------
# Single UAMI federated to ALL function-app deploy environments. Each consumer
# repo + GH environment gets its own federated credential (FIC) on this single
# UAMI, but they all surface the SAME clientId. The legacy per-app deploy
# UAMIs (id-scalein-ghrunners-deploy, id-scaleout-webhook-ghrunners-deploy)
# were destroyed and replaced by this consolidation on 2026-04-27.
#
# Why one UAMI:
# - Single rotation point — recreate this UAMI and all consumers update via
#   the TF-managed env secrets below
# - Eliminates per-app stale-clientId failure modes (the b5e33478 vs 6b6c00e0
#   incident on 2026-04-26 happened because a destroy/recreate of one UAMI
#   only updated one consumer's secret out-of-band)
# - Simpler mental model: "the deploy identity" is a single principal
#
# Tradeoff: blast radius is the union of all role assignments granted to the
# principal. Mitigated by scoping each role assignment to a single function
# app rather than RG-wide. A compromised deploy workflow could still touch
# all function apps, but not anything outside that surface (storage,
# networking, KV, VMSS).
#
# Adding a new consumer (new repo+env combo):
# 1. Add an azurerm_federated_identity_credential block here with the new
#    subject (repo:owner/repo:environment:env-name)
# 2. Add an azurerm_role_assignment in runtime/role-assignments.tf scoped
#    to the target function app
# 3. Add a github_actions_environment_secret block (below) that pushes
#    AZURE_CLIENT_ID to the consumer repo's env
#
# See .claude/Docs/Tracking/2026-04-26-gh-env-secrets-for-deploy-uami.md
# for the full env-secret handshake reasoning.
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "deploy" {
  count = var.create_unified_deploy_identity ? 1 : 0

  name                = "id-ghrunners-deploy"
  location            = coalesce(var.deploy_identity_location, var.location)
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# FIC: ScaleIn function repo, production env
resource "azurerm_federated_identity_credential" "deploy_scalein_prod" {
  count = var.create_unified_deploy_identity ? 1 : 0

  name                = "github-scalein-env-production"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.deploy[0].id
  subject             = "repo:eh-ciellos/ScaleInVmssFunction:environment:production"
}

# FIC: ScaleOut function repo, webhook-production env (Phase 2B App A — GhWebHookScaleOut)
resource "azurerm_federated_identity_credential" "deploy_scaleout_webhook_prod" {
  count = var.create_unified_deploy_identity ? 1 : 0

  name                = "github-scaleout-webhook-env-production"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.deploy[0].id
  subject             = "repo:eh-ciellos/ScaleOutVmssFunction:environment:webhook-production"
}

# FIC: ScaleOut function repo, production env (App B — ProcVmssScaleQueue)
resource "azurerm_federated_identity_credential" "deploy_scaleout_queue_prod" {
  count = var.create_unified_deploy_identity ? 1 : 0

  name                = "github-scaleout-queue-env-production"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.deploy[0].id
  subject             = "repo:eh-ciellos/ScaleOutVmssFunction:environment:production"
}

# -----------------------------------------------------------------------------
# Option A: TF manages the AZURE_CLIENT_ID env-scoped GitHub secrets.
# When the unified UAMI gets recreated (or its clientId otherwise changes),
# both consumer repos' env secrets follow automatically. Eliminates the
# stale-clientId class of bug forever.
#
# Requires var.github_secrets_pat — a GH PAT with `secrets: write` (or
# fine-grained equivalent) on both eh-ciellos/ScaleInVmssFunction and
# eh-ciellos/ScaleOutVmssFunction. Set as the GH_SECRETS_PAT secret on
# this repo and passed via TF_VAR_github_secrets_pat.
#
# When PAT is empty (default), the secret resources are NOT created and
# consumer repos retain whatever AZURE_CLIENT_ID values are already set
# (manual operational mode). This makes the PAT requirement opt-in: the
# UAMI + FICs work without it; only the secret auto-sync is gated.
# -----------------------------------------------------------------------------

# Gotcha-2 permanent fix (referenced by lifecycle.replace_triggered_by on
# all 6 sub-correlated env-secrets below). Closes the drift-blind class
# documented in tf-04 / 00-tf-overview's sub-switch playbook.
#
# Mechanic: terraform_data is a built-in state-tracked resource whose
# `input` attribute is hashed into state. When `data.azurerm_client_config
# .current.subscription_id` evaluates to a new value (i.e., we're on a
# different sub), the keeper's input changes → terraform_data is replaced
# → every secret with lifecycle.replace_triggered_by = [terraform_data
# .sub_id_keeper] is forced to delete + create. That delete+create cycle
# is what writes the fresh value to GitHub (sidestepping the write-only
# API drift-blindness).
#
# Why one keeper per module (this one + one in root's
# github-image-builder-secret.tf): replace_triggered_by requires DIRECT
# resource references, not module outputs. Two keepers driven by the
# same data source value stay in lockstep.
#
# Operational note: on the first apply after this lands, terraform_data
# .sub_id_keeper is created fresh. The 6 secrets DO NOT replace on that
# first apply because the dependency just exists at its current value,
# not changes. The replace-on-change behavior kicks in starting on the
# NEXT sub switch.
resource "terraform_data" "sub_id_keeper" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0
  input = data.azurerm_client_config.current.subscription_id
}

resource "github_actions_environment_secret" "scalein_deploy_client_id" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository      = "ScaleInVmssFunction"
  environment     = "production"
  secret_name     = "AZURE_CLIENT_ID"
  plaintext_value = azurerm_user_assigned_identity.deploy[0].client_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

resource "github_actions_environment_secret" "scaleout_webhook_deploy_client_id" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository      = "ScaleOutVmssFunction"
  environment     = "webhook-production"
  secret_name     = "AZURE_CLIENT_ID"
  plaintext_value = azurerm_user_assigned_identity.deploy[0].client_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

# Mirror of the webhook env secret for App B's deploy env (ProcVmssScaleQueue
# uses the `production` env on the same repo). Closes the parity gap left when
# deploy_scaleout_queue_prod FIC + deploy_scaleout_website_contributor role
# were added without a corresponding TF-managed env secret — ScaleOut agent
# had to set AZURE_CLIENT_ID via `gh secret set` manually on 2026-05-07.
resource "github_actions_environment_secret" "scaleout_queue_deploy_client_id" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository      = "ScaleOutVmssFunction"
  environment     = "production"
  secret_name     = "AZURE_CLIENT_ID"
  plaintext_value = azurerm_user_assigned_identity.deploy[0].client_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

# -----------------------------------------------------------------------------
# GitHub env-secret AZURE_SUBSCRIPTION_ID (consumer-side sub ID auto-rotation)
# -----------------------------------------------------------------------------
# Closes the "third gotcha" surfaced by ScaleOut agent on 2026-05-22 (doc 19):
# AZURE_SUBSCRIPTION_ID was previously a repo-level secret set manually, so
# every sub switch required an out-of-band `gh secret set` on each consumer
# repo or OIDC login would fail with "subscription ... doesn't exist in cloud".
#
# Now correlated with the AZURE_CLIENT_ID env-secret resources above: when
# TF runs against a different Azure sub, the data source re-evaluates and
# TF planning sees a new value for both clientId AND subscription ID, so
# both rotate as a pair on the next apply post-switch.
#
# Known caveat (carried forward from gotcha 2): GitHub's secrets API is
# write-only, so the provider can't detect drift for resources already in
# state. After the first apply post-switch, subsequent switches may need a
# manual `gh secret set` rotation for the same reason. A future PR could
# wire `lifecycle.replace_triggered_by` against a `terraform_data` keyed on
# the sub ID to force re-create, applied uniformly across all 6 env-secrets.
# Out of scope here to keep this PR focused on the third-gotcha closure.
# -----------------------------------------------------------------------------

resource "github_actions_environment_secret" "scalein_subscription_id" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository      = "ScaleInVmssFunction"
  environment     = "production"
  secret_name     = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

resource "github_actions_environment_secret" "scaleout_webhook_subscription_id" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository      = "ScaleOutVmssFunction"
  environment     = "webhook-production"
  secret_name     = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

resource "github_actions_environment_secret" "scaleout_queue_subscription_id" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository      = "ScaleOutVmssFunction"
  environment     = "production"
  secret_name     = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

# -----------------------------------------------------------------------------
# GitHub env VARIABLES — Function app names (consumer-repo discovery)
# -----------------------------------------------------------------------------
# Publishes the target function app name to each consumer repo's deploy
# environment. Closes the hardcoded-name gap ScaleIn hit on the 2026-05-07
# sub switch: the unique_suffix changed from -4fa2 to -1981, function apps
# got renamed, and their workflow's hardcoded `func-scalein-...-4fa2`
# silently broke until manually patched in their PR #3.
#
# Pairs with the AZURE_CLIENT_ID env-secret resources above: on the next
# sub switch (or any other naming change), TF rotates BOTH the deploy
# clientId AND the target function app name in the consumer's env config.
# Consumer workflows read `${{ vars.AZURE_FUNCTIONAPP_NAME }}` instead of
# hardcoding.
#
# Same predicate as the env-secret resources for consistency. Gated on
# var.github_secrets_pat (which must be a fine-grained PAT with
# `Variables: write` + `Environments: read` on the consumer repos).
# Environments and Variables go through the same GH endpoint family, so
# the PAT that already manages secrets typically covers variables too.
# -----------------------------------------------------------------------------

resource "github_actions_environment_variable" "scalein_function_app_name" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository    = "ScaleInVmssFunction"
  environment   = "production"
  variable_name = "AZURE_FUNCTIONAPP_NAME"
  value         = var.resource_names.func_scalein
}

resource "github_actions_environment_variable" "scaleout_queue_function_app_name" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository    = "ScaleOutVmssFunction"
  environment   = "production"
  variable_name = "AZURE_FUNCTIONAPP_NAME"
  value         = var.resource_names.func_scaleout
}

resource "github_actions_environment_variable" "scaleout_webhook_function_app_name" {
  count = var.create_unified_deploy_identity && var.github_secrets_pat != "" ? 1 : 0

  repository    = "ScaleOutVmssFunction"
  environment   = "webhook-production"
  variable_name = "AZURE_FUNCTIONAPP_NAME"
  value         = var.resource_names.func_scaleout_webhook
}

# -----------------------------------------------------------------------------
# Image Builder OIDC — FIC + sub-wide Contributor for id-ghrunners-image-builder
# -----------------------------------------------------------------------------
# Migrates gitspacecadet/vm-runner-image from legacy SP+client-secret auth to
# OIDC (parallel to the unified-deploy pattern above, but with separate UAMI
# for blast-radius isolation). The FIC subject is environment-based — any
# branch allowed by the GH "image-build" environment's protection rules can
# mint a token. Sub-wide Contributor scope matches what Packer needs (temp RG
# creation, gallery version push). Consumer-side secrets (CLIENT_ID, SUB_ID,
# TENANT_ID) are pushed by github_actions_secret resources in the ROOT module
# (terraform/github-image-builder-secret.tf) because they use the
# github.image_builder_scope provider alias which can't be threaded into
# child modules without complex provider routing.
#
# Reference: FromVmImageAgent/21-extend-oidc-pattern-to-image-builder-2026-05-22.md
# -----------------------------------------------------------------------------

# Sub data source used only by the image-builder role-assignment scope.
# Declared here (vs. somewhere upstream) to keep image-builder concerns
# co-located. Cheap to evaluate — single ARM lookup per plan.
data "azurerm_subscription" "current" {}

resource "azurerm_federated_identity_credential" "image_builder_env" {
  count = var.create_image_builder_identity ? 1 : 0

  name                = "github-vm-runner-image-env-image-build"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.image_builder[0].id
  subject             = "repo:gitspacecadet/vm-runner-image:environment:image-build"
}

resource "azurerm_role_assignment" "image_builder_subscription_contributor" {
  count = var.create_image_builder_identity ? 1 : 0

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder[0].principal_id
}
