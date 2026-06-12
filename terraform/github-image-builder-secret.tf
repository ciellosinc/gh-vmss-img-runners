# -----------------------------------------------------------------------------
# AZURE_SUBSCRIPTION_ID repo-level secret on gitspacecadet/vm-runner-image
# -----------------------------------------------------------------------------
# Companion to the env-scoped AZURE_SUBSCRIPTION_ID resources in
# modules/foundation/deploy-identities.tf (which cover the eh-ciellos
# function-app repos). This block extends the same TF-ownership pattern
# to the Packer image-build repo, closing the build-failure-after-sub-
# switch class that bit us on 2026-05-22 (vm-image doc 20: Packer crashed
# at StepCreateResourceGroup with ReadOnlyDisabledSubscription because
# AZURE_SUBSCRIPTION_ID still pointed at the disabled Emanuele sub).
#
# Why repo-level (not env-scoped) here:
# vm-runner-image's BuildALGoRunnerImage.yaml workflow reads repo-level
# secrets via azure/login@v2 — it doesn't use GH Environments. So the
# right pairing is github_actions_secret + secrets.AZURE_SUBSCRIPTION_ID,
# not the github_actions_environment_secret pattern used for function-app
# deploy lanes.
#
# Idempotency note: GitHub's repo-secrets API uses PUT (upsert), unlike
# the env-VARIABLES API which uses POST and 409s on conflict. So the
# first apply silently overwrites the manually-set value vm-image agent
# wrote on 2026-05-22T15:15:41Z — no delete-then-recreate dance, same
# value (Yevgeni sub ID), TF takes ownership cleanly.
#
# Same drift-blind quirk (gotcha 2) carries forward: GitHub's secrets API
# is write-only, so after the first apply post-switch the resource sits
# in state and the provider doesn't replay it on subsequent applies even
# if the data source value changes. Documented limitation; same future
# fix (lifecycle.replace_triggered_by against a sub-id keeper) would
# uniformly resolve across all 7 env+repo-scoped sub-id secrets.
# -----------------------------------------------------------------------------

# Gotcha-2 permanent fix companion to terraform_data.sub_id_keeper in
# modules/foundation/deploy-identities.tf. Same mechanic: when sub_id
# changes, the keeper is replaced, which forces replacement of every
# secret with replace_triggered_by pointing here.
#
# Why a SECOND keeper instead of referencing the foundation one: TF's
# lifecycle.replace_triggered_by requires direct resource references
# (not module outputs). The 2 root-module secrets below can't reach the
# foundation keeper. Two keepers driven by the same data source value
# stay in lockstep — both replace simultaneously on sub switch.
#
# Skipping vm_runner_image_tenant_id (below) because tenant_id is
# invariant across all our subs (same Ciellos tenant). Replace-on-
# sub-change would be pure noise for that one.
resource "terraform_data" "sub_id_keeper" {
  count = var.create_image_builder_identity && var.github_image_builder_pat != "" ? 1 : 0
  input = data.azurerm_client_config.current.subscription_id
}

resource "github_actions_secret" "vm_runner_image_subscription_id" {
  provider = github.image_builder_scope

  count = var.create_image_builder_identity && var.github_image_builder_pat != "" ? 1 : 0

  repository      = "vm-runner-image"
  secret_name     = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

# -----------------------------------------------------------------------------
# OIDC migration companions to vm_runner_image_subscription_id above
# -----------------------------------------------------------------------------
# Added by the FromVmImageAgent/21 migration (image-builder UAMI + OIDC FIC).
# These two secrets, combined with the existing sub-id secret above, give
# vm-runner-image the same auto-rotation contract on sub switches that
# ScaleIn/ScaleOut enjoy via the env-scoped secrets in deploy-identities.tf.
#
# Why these two need a module output detour:
# - AZURE_CLIENT_ID reads from the image_builder UAMI's client_id, which lives
#   in the foundation module. We bridge via module.foundation.image_builder_client_id.
# - AZURE_TENANT_ID reads from data.azurerm_client_config.current.tenant_id which
#   is available directly in the root (no detour needed).
#
# Once these land in vm-runner-image, vm-image agent can update their workflow's
# azure/login@v2 step to OIDC and retire the legacy AZURE_CLIENT_SECRET. Steps
# A-D in their doc 21.
# -----------------------------------------------------------------------------

resource "github_actions_secret" "vm_runner_image_client_id" {
  provider = github.image_builder_scope

  count = var.create_image_builder_identity && var.github_image_builder_pat != "" ? 1 : 0

  repository      = "vm-runner-image"
  secret_name     = "AZURE_CLIENT_ID"
  plaintext_value = module.foundation.image_builder_client_id

  lifecycle {
    replace_triggered_by = [terraform_data.sub_id_keeper]
  }
}

resource "github_actions_secret" "vm_runner_image_tenant_id" {
  provider = github.image_builder_scope

  count = var.create_image_builder_identity && var.github_image_builder_pat != "" ? 1 : 0

  repository      = "vm-runner-image"
  secret_name     = "AZURE_TENANT_ID"
  plaintext_value = data.azurerm_client_config.current.tenant_id
}
