# Step 3 — Seed GitHub secrets and variable

> **Performed by:** GitHub Repo Admin (someone with permission to write Actions secrets and variables on the target repo)

---

## What you'll need

| Item | Where from |
|---|---|
| Step 1 output (Client ID, Tenant ID) | `./Installation/.bootstrap-output.json` (or copy from Step 1 stdout) |
| Step 2 output (Storage Account Name) | ARM deployment Outputs tab, or your worked-example notes |
| Subscription ID | Same as Step 1 |
| **`GH_PAT` value** | Your fine-grained PAT — see scope requirements below |
| **`VMSS_ADMIN_PASSWORD` value** | A strong password meeting Azure VMSS complexity rules |

---

## What this step creates

| Where | What | Type |
|---|---|---|
| Repo-level secrets (5) | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `GH_PAT`, `VMSS_ADMIN_PASSWORD` | secret |
| Repo-level secrets (3 optional) | `GH_SECRETS_PAT`, `GH_IMAGE_BUILDER_PAT`, `GH_ORGANIZATION` | secret |
| Repo-level variable (1) | `TFSTATE_STORAGE_ACCOUNT` | variable (not secret) |

---

## Instructions

### 3.1 — Run the script

```pwsh
./Installation/scripts/Set-GitHubSecrets.ps1 `
    -GitHubOrg '<your-github-org>' `
    -GitHubRepo '<your-repo-name>' `
    -SubscriptionId '<your-sub-id>' `
    -StorageAccountName '<from-step-2>' `
    -InputPath './Installation/.bootstrap-output.json'
```

The script prompts (with secure input masking) for `GH_PAT` and `VMSS_ADMIN_PASSWORD`. To pre-supply them non-interactively:

```pwsh
$pat = Read-Host 'GH_PAT' -AsSecureString
$pwd = Read-Host 'VMSS_ADMIN_PASSWORD' -AsSecureString
./Installation/scripts/Set-GitHubSecrets.ps1 `
    -GitHubOrg '<...>' -GitHubRepo '<...>' `
    -SubscriptionId '<...>' -StorageAccountName '<...>' `
    -InputPath './Installation/.bootstrap-output.json' `
    -GhPat $pat -VmssAdminPassword $pwd
```

The script is **idempotent** — re-running overwrites the secrets with the same (or new) values. GitHub does not log secret value diffs.

### 3.2 — Mandatory secrets reference

| Secret | Purpose | Source |
|---|---|---|
| `AZURE_CLIENT_ID` | OIDC login from `azure/login@v2` action | Step 1: `SpClientId` |
| `AZURE_TENANT_ID` | OIDC tenant | Step 1: `TenantId` |
| `AZURE_SUBSCRIPTION_ID` | Target sub for TF apply | Param |
| `GH_PAT` | Runner registration + release lookups | Your fine-grained PAT |
| `VMSS_ADMIN_PASSWORD` | VMSS local admin (TF_VAR) | You pick |

### 3.3 — `GH_PAT` required scopes

The `GH_PAT` is consumed by:

1. The Custom Script Extension on each VMSS instance (`Initialize-GhRunner.ps1`) to register the runner against the target GitHub org
2. The `terraform-deploy.yml` workflow (release-lookup steps that resolve latest VMSS image versions)
3. The ScaleIn janitor on the function app (`GITHUB_RECONCILE_TOKEN`) — queries workflow-run state to detect stuck VMs

Required scopes for a fine-grained PAT:

| Scope | Level | Why |
|---|---|---|
| **Self-hosted runners: Read and write** | Organization | Register/deregister runners |
| **Administration: Read and write** | Organization | List runners + remove orphans |
| **Actions: Read and write** | Repository (all runner-target repos) | Read workflow run state; required by ScaleIn janitor |
| **Metadata: Read** | Repository | API base-level access |
| **Contents: Read** | Repository | Release-lookup queries |

> **Don't have a PAT with these scopes yet?** See the step-by-step UI walkthrough in **[Scenarios/Create-GhPat.md](../Scenarios/Create-GhPat.md)** — covers exactly which fields to fill on `https://github.com/settings/personal-access-tokens/new`, with screenshots of the permission selectors.

> **Why `Actions: R/W` on all runner-target repos:** the ScaleIn janitor queries `actions/runs/<id>` on every repo it might attribute a stuck VM to. Without `actions:read` on a given repo, the janitor returns 404 and conservatively defers — leaving stuck VMs uncleared.

### 3.4 — Optional secrets reference

| Secret | When you need it | Source |
|---|---|---|
| `GH_SECRETS_PAT` | When you want TF to auto-sync `AZURE_*` env secrets to the consumer repos (ScaleIn / ScaleOut) | Fine-grained PAT with Secrets: R/W + Environments: R/W on the consumer repos |
| `GH_IMAGE_BUILDER_PAT` | When you want TF to auto-sync `AZURE_*` secrets to `vm-runner-image` | Fine-grained PAT with Secrets: R/W on `vm-runner-image` |
| `GH_ORGANIZATION` | When runners register to a DIFFERENT org than `-GitHubOrg` | The runner-target org name. Defaults to `-GitHubOrg` if omitted. |

Skip these if you don't have the consumer-repo wiring set up — TF will gracefully skip those modules.

### 3.5 — Repo variables (5)

Five GitHub repo **variables** (not secrets — plaintext in workflow logs) parameterize Terraform inputs so operators can customize without editing `backend.tf` or `*.tfvars`:

**State backend** (3 — from Step 2 choices):

| Variable | Default | What it backs |
|---|---|---|
| `TFSTATE_STORAGE_ACCOUNT` | (no default — required) | `backend "azurerm" { storage_account_name = ... }` |
| `TFSTATE_RESOURCE_GROUP_NAME` | `rg-terraform-state` | `backend "azurerm" { resource_group_name = ... }` (your portal-form choice) |
| `TFSTATE_CONTAINER_NAME` | `tfstate` | `backend "azurerm" { container_name = ... }` |

Workflows read these via `-backend-config="<key>=${{ vars.<NAME> }}"` on `terraform init`. Unset → falls back to default → existing installs on `rg-terraform-state` / `tfstate` keep working.

**Runtime infra** (2 — distinct from the state backend's region; this is where VMSS + KV + functions + gallery + everything else actually run):

| Variable | Default | What it backs |
|---|---|---|
| `RUNTIME_LOCATION` | `centralus` | TF variable `location` (full Azure region name). Exported by the workflow as `TF_VAR_location` env var. |
| `RUNTIME_REGION_SUFFIX` | `cus` | TF variable `region` (short suffix in resource names like `rg-ghrunners-dev-cus`). Exported as `TF_VAR_region`. |

> **Important: state backend region ≠ runtime region.** Step 2's portal form region only controls where the state RG/SA/container live. The runtime infra (VMSS, KV, functions, gallery) lives wherever `RUNTIME_LOCATION` says. These CAN match (clean), or they CAN differ (you have a sub-region preference for state vs. workloads). Operators usually want them to match.

If you used non-default names in Step 2 OR want runtime infra in a non-default region, pass them to `Set-GitHubSecrets.ps1` via:

```pwsh
./Set-GitHubSecrets.ps1 `
    -GitHubOrg '<your-org>' -GitHubRepo '<your-repo>' `
    -SubscriptionId '<sub>' -StorageAccountName '<sa>' `
    -TfStateResourceGroupName 'rg-ghvmss-tf-state' `       # ← your state-backend RG (Step 2)
    -TfStateContainerName 'tfstate' `                       # ← default if you kept it
    -RuntimeLocation 'eastus2' `                            # ← Azure region for runtime infra
    -RuntimeRegionSuffix 'eus2' `                           # ← short suffix used in resource names
    -InputPath '..\.bootstrap-output.json'
```

Common `RUNTIME_LOCATION` → `RUNTIME_REGION_SUFFIX` pairings (pick what matches your operator naming convention):

| Location | Suffix |
|---|---|
| `centralus` | `cus` |
| `eastus` | `eus` |
| `eastus2` | `eus2` |
| `westus2` | `wus2` |
| `westeurope` | `weu` |
| `northeurope` | `neu` |

> **Why variables instead of secrets:** workflow log readability + the values aren't sensitive (storage account / RG / container names + region info aren't secret; the AAD-only access policy keeps state-backend data safe even when the names are public).

---

## Verify before continuing

```bash
# Mandatory secret names (you can't read values via API, only names)
gh secret list --repo '<your-org>/<your-repo>' --json name --jq '.[].name'
# Expected: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, GH_PAT, VMSS_ADMIN_PASSWORD, plus optional ones

# Variable value (variables ARE readable)
gh variable list --repo '<your-org>/<your-repo>' --json name,value --jq '.[] | select(.name=="TFSTATE_STORAGE_ACCOUNT")'
# Expected: { "name": "TFSTATE_STORAGE_ACCOUNT", "value": "<from-step-2>" }
```

Or run [Step 4 — `Verify-Prereqs.ps1`](Step4-Verify.md).

---

## Worked example (placeholder — filled in during the live switch)

> **Worked example — `<YYYY-MM-DD>` install on `<new-org>` / `<new-sub>`**
>
> Command run:
> ```pwsh
> ./Installation/scripts/Set-GitHubSecrets.ps1 `
>     -GitHubOrg '<TBD>' -GitHubRepo 'gh-vmss-img-runners' `
>     -SubscriptionId '<TBD>' -StorageAccountName '<TBD>' `
>     -InputPath './Installation/.bootstrap-output.json'
> ```
>
> PAT identity used as `GH_PAT`: `<TBD — name of fine-grained PAT in GitHub UI>`
> Optional secrets set: `<TBD>`
> Anything noteworthy: _(filled in during execution)_

---

**Next step:** **[Step 4 — Verify prereqs](Step4-Verify.md)**
