# Step 5 — Dispatch the first Terraform deploy

> **Performed by:** GitHub Repo Admin (or anyone with `workflow_dispatch` permission on the target repo)

This is the moment the runner infrastructure comes to life. Steps 1-4 set up the conditions; Step 5 is "press the button."

---

## What you'll need

- All of Steps 1-4 complete
- [`Verify-Prereqs.ps1`](Step4-Verify.md) returned 0 / all green
- Browser access to the GitHub Actions tab (or `gh` CLI with `workflow` scope)

---

## What this step creates

The first `terraform apply` lands the **runtime infrastructure** on the `dev` environment:

| What | From which TF module | Notes |
|---|---|---|
| Resource group `rg-ghrunners-dev-<region-short>` | `modules/foundation/` | Hosts everything below |
| Key Vault `kv-ghrunners-dev-<region-short>` | `modules/foundation/key-vault.tf` | Stores `github-pat` (mirrored from `GH_PAT`) |
| Log Analytics workspace | `modules/foundation/log-analytics.tf` | Telemetry sink |
| User-assigned managed identities | `modules/foundation/deploy-identities.tf` | For ScaleIn / ScaleOut / VMSS / image-builder consumers |
| VNet + NSG + ILB | `modules/foundation/networking.tf` | Internal-only network |
| Storage accounts (function apps) | `modules/foundation/storage.tf` | Backing for ScaleIn + ScaleOut functions |
| Compute Gallery + image definition | `modules/foundation/compute-gallery.tf` | Referenced by VMSS |
| VMSS (capacity = 0) | `modules/runtime/vmss.tf` | Scales up on demand via ScaleOut |
| 2 Function Apps (scale-out + scale-in) | `modules/runtime/function-app.tf` | Deployed code arrives via consumer-repo workflows after first apply |
| 2 Application Insights instances | `modules/runtime/monitoring.tf` | Per function app |
| Role assignments | `modules/runtime/role-assignments.tf` | RBAC for the runtime identities |

---

## Instructions

### 5.1 — Dispatch the workflow

**Option A: GitHub UI**

1. Go to the repo's **Actions** tab
2. Select the **terraform-deploy** workflow from the left sidebar
3. Click **Run workflow** (top-right)
4. Pick:
   - Branch: `main`
   - Environment: `dev`
   - Action: `apply`
5. Click **Run workflow**

**Option B: CLI**

```bash
gh workflow run terraform-deploy.yml \
  --repo '<your-org>/<your-repo>' \
  --ref main \
  -f environment=dev \
  -f action=apply
```

### 5.2 — What to watch for

The workflow has three meaningful phases — watch each succeed before assuming the next will:

| Phase | What happens | If it fails… |
|---|---|---|
| **init** | `terraform init` connects to the backend storage account using the SP via OIDC | Step 2 or Step 3 issue (RBAC, sub mismatch, or wrong storage account name) |
| **plan** | TF computes the resource graph | Likely a tfvars issue or a missing variable |
| **apply** | TF creates the resources | First apply takes 8–15 minutes |

### 5.3 — Expected timing

| Phase | Typical duration on a clean sub |
|---|---|
| init | 30–60 s |
| plan | 1–3 min |
| apply | 8–15 min |
| **Total** | **10–20 min** |

> **Why so long for apply:** the Function Apps + their App Service Plans take ~3-5 minutes to provision; the Compute Gallery image definition takes ~1 min; VMSS creation (even at capacity 0) takes ~2 min. These run mostly in parallel but TF respects dependency edges.

---

## After the apply succeeds

### 5.4 — Verify the runtime exists

```bash
# Set context to your dev environment (region varies)
DEV_RG="rg-ghrunners-dev-cus"   # adjust if you picked a different region

# VMSS exists at capacity 0 (scale-to-zero is the default)
az vmss show -g $DEV_RG -n vmss-ghrunners-dev-cus --query 'sku.capacity' -o tsv
# Expected: 0

# 2 Function Apps exist (no code yet — that's deployed by consumer repos)
az functionapp list -g $DEV_RG --query "[].name" -o tsv
# Expected: func-scaleout-ghrunners-dev-cus AND func-scalein-ghrunners-dev-cus
# (or webhook + queue variants if ScaleOut is split-mode)

# Key Vault exists with the bootstrap secrets
az keyvault secret show --vault-name kv-ghrunners-dev-cus --name github-pat --query 'attributes.enabled' -o tsv
# Expected: true
```

### 5.5 — Deploy the function app code

The TF apply provisions the Function App *shells*. The actual function code lives in sibling repos:

| Consumer repo | What it deploys |
|---|---|
| `<your-org>/ScaleOutVmssFunction` | ScaleOut function code (webhook + queue processor) |
| `<your-org>/ScaleInVmssFunction` | ScaleIn function code (timer + janitor) |
| `<your-org>/vm-runner-image` | Packer image build + Compute Gallery upload |

If TF auto-synced the consumer-repo env secrets (because you set `GH_SECRETS_PAT` and `GH_IMAGE_BUILDER_PAT` in Step 3), each consumer repo can run their deploy workflow without further setup. Otherwise: set `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` on the consumer repos' deploy environments first.

### 5.6 — Smoke-test scale-out

Trigger a workflow on a runner-target repo (one whose workflow uses `runs-on: [self-hosted, vmss-dev]` or similar label). Watch:

1. ScaleOut function receives the webhook (Application Insights → traces)
2. ScaleOut increases VMSS capacity by 1
3. New VM boots (~3-5 min)
4. Custom Script Extension runs `Initialize-GhRunner.ps1`, registers the runner
5. Workflow job assigns to the new runner
6. After job completes, ScaleIn marks the VM idle, reaps after `POOL_TTL_MINUTES`

If you don't see scale-out within ~30 seconds of dispatching the runner-target workflow, check:
- VMSS image is published in the Compute Gallery (needs the `vm-runner-image` workflow to have run at least once)
- Webhook is registered on the runner-target repo and points at `https://func-scaleout-webhook-ghrunners-dev-cus.azurewebsites.net/api/webhook`
- ScaleOut function code is deployed (run the workflow in `<your-org>/ScaleOutVmssFunction`)

---

## Worked example (placeholder — filled in during the live switch)

> **Worked example — `<YYYY-MM-DD>` install on `<new-org>` / `<new-sub>`**
>
> Workflow dispatched: `<run-id>`
> Init duration: `<TBD>`
> Plan duration: `<TBD>`
> Apply duration: `<TBD>`
> Resources created: `<TBD>`
> Smoke-test result: `<TBD>`
> Anything noteworthy: _(filled in during execution)_

---

## Where to go from here

- **Ongoing operations:** [`Pipelines/README.md`](../Pipelines/README.md) (workflow operator handbook)
- **Architecture context:** [`.claude/Docs/Tracking/system-reference/`](../.claude/Docs/Tracking/system-reference/) (internal TF reference)
- **Troubleshooting:** [Appendix B](AppendixB-Troubleshooting.md)
- **Switching to GitHub App auth:** [Appendix A](AppendixA-GitHubAppAuth.md)

🎉 **You're done with installation.**
