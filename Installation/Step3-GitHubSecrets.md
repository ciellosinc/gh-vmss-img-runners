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

Required scopes for a fine-grained PAT:

| Scope | Level | Why |
|---|---|---|
| **Self-hosted runners: Read and write** | Organization | Register/deregister runners |
| **Administration: Read and write** | Organization | List runners + remove orphans |
| **Actions: Read and write** | Repository (all runner-target repos) | Read workflow run state; required by ScaleIn janitor |
| **Metadata: Read** | Repository | API base-level access |
| **Contents: Read** | Repository | Release-lookup queries |

> **Why `Actions: R/W` on all runner-target repos:** the ScaleIn janitor queries `actions/runs/<id>` on every repo it might attribute a stuck VM to. Without `actions:read` on a given repo, the janitor returns 404 and conservatively defers — leaving stuck VMs uncleared. See [memory `project_pat_identity_mapping.md`](../../.claude/CLAUDE.md) for the design history of this scope decision.

### 3.4 — Optional secrets reference

| Secret | When you need it | Source |
|---|---|---|
| `GH_SECRETS_PAT` | When you want TF to auto-sync `AZURE_*` env secrets to the consumer repos (ScaleIn / ScaleOut) | Fine-grained PAT with Secrets: R/W + Environments: R/W on the consumer repos |
| `GH_IMAGE_BUILDER_PAT` | When you want TF to auto-sync `AZURE_*` secrets to `vm-runner-image` | Fine-grained PAT with Secrets: R/W on `vm-runner-image` |
| `GH_ORGANIZATION` | When runners register to a DIFFERENT org than `-GitHubOrg` | The runner-target org name. Defaults to `-GitHubOrg` if omitted. |

Skip these if you don't have the consumer-repo wiring set up — TF will gracefully skip those modules.

### 3.5 — Repo variable

`TFSTATE_STORAGE_ACCOUNT` is a **variable**, not a secret (its value is plaintext in workflow logs). It's the storage account name from Step 2 and is consumed by `terraform init -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT"`.

> **Why variable instead of secret:** workflow log readability + the value isn't sensitive (storage accounts aren't secret; the AAD-only access policy keeps them safe even when the name is public).

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
