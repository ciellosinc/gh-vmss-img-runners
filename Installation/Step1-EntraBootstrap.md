# Step 1 — Bootstrap the Entra side

> **Performed by:** Azure Subscription Owner **+** Entra ID Application Administrator **+** GitHub Repo Admin
>
> One operator with all three roles is fine. If split across people, all three need to be on the same Azure tenant + GitHub session.

---

## What you'll need

| Item | Example | Where to get it |
|---|---|---|
| GitHub org name | `gitspacecadet` | The org that owns the repo (or a user account name) |
| GitHub repo name | `gh-vmss-img-runners` | The repo as you'd type it in a URL |
| Azure subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | `az account show --query id -o tsv` after `az login` |
| `az` session | (signed in) | `az login` with an account that has Owner on the sub |
| `gh` session | (signed in) | `gh auth login` with admin:org + admin:repo scopes |

---

## What this step creates

| In Azure (Entra) | In GitHub |
|---|---|
| 1 service principal `GitHub-OIDC-GHRunners-<your-org>` | 6 environments: `dev`, `test`, `prod`, `dev-plan`, `test-plan`, `prod-plan` |
| Contributor role on the subscription, assigned to the SP | (FICs on the SP federate to these — see column at left) |
| User Access Administrator role on the subscription, assigned to the SP | |
| 6 federated identity credentials on the SP, one per GH environment | |

No secrets, no PATs — OIDC only.

---

## Instructions

### 1.1 — Run the script

From the repo root:

```pwsh
./Installation/scripts/Bootstrap-Entra.ps1 `
    -GitHubOrg '<your-github-org>' `
    -GitHubRepo '<your-repo-name>' `
    -SubscriptionId '<your-sub-id>' `
    -OutputPath './Installation/.bootstrap-output.json'
```

The script is **idempotent** — running it twice is safe. Existing resources are reported as `[Exists]` and left untouched.

> **Why org-namespaced SP name:** the default `GitHub-OIDC-GHRunners-<your-org>` keeps the SP per-tenant scoped to one GitHub org. If you install this stack into a tenant that hosts multiple GitHub orgs in the future, they won't collide.

### 1.2 — Capture the output

The last lines printed will look like this:

```
Capture these values for the next steps:
  SP Client ID    (AZURE_CLIENT_ID)       : aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb
  SP Object ID    (for ARM template input): ccccccc-4444-5555-6666-dddddddddddd
  Tenant ID       (AZURE_TENANT_ID)       : eeeeeeee-7777-8888-9999-ffffffffffff
  Subscription ID (AZURE_SUBSCRIPTION_ID) : <your-sub-id>
```

You'll paste these into Step 2 (the **Object ID**) and Step 3 (the **Client ID**, **Tenant ID**, **Subscription ID**).

If you passed `-OutputPath`, the same values are written as JSON to that path. Steps 2/3/4 can read it directly via `-InputPath`, so you don't have to copy-paste.

> **Why pass the Object ID — not the Client ID — to Step 2:** Azure role assignments target the **service principal object** (the directory entry), not the **application** (the registered app). The two share a `displayName` but have different IDs. Step 2's ARM template grants Storage Blob Data Contributor and needs the SP's `objectId`.

### 1.3 — What if I need to undo this step?

```pwsh
# Remove the SP (this also removes its role assignments and FICs)
az ad sp delete --id <SP-Object-Id>
az ad app delete --id <App-Object-Id>

# Remove the GH environments (one per env)
gh api -X DELETE "repos/<org>/<repo>/environments/<env>"
```

You can also just re-run `Bootstrap-Entra.ps1` with a different `-SpName` to create a parallel SP and migrate at your own pace.

---

## Verify before continuing

```bash
# SP exists with the right role assignments
az ad sp list --filter "displayName eq 'GitHub-OIDC-GHRunners-<your-org>'" --query '[0].id' -o tsv
az role assignment list \
  --assignee-object-id <SP-Object-Id> \
  --scope /subscriptions/<your-sub-id> \
  --query '[].roleDefinitionName' -o tsv
# Expected: Contributor + User Access Administrator

# GitHub environments exist
gh api "repos/<org>/<repo>/environments" --jq '.environments[].name'
# Expected: dev, test, prod, dev-plan, test-plan, prod-plan
```

Or just run [Step 4 — `Verify-Prereqs.ps1`](Step4-Verify.md) — it does all of this in one go.

---

## Worked example (placeholder — filled in during the live switch)

> **Worked example — `<YYYY-MM-DD>` install on `<new-org>` / `<new-sub>`**
>
> Command run:
> ```pwsh
> ./Installation/scripts/Bootstrap-Entra.ps1 `
>     -GitHubOrg '<TBD>' `
>     -GitHubRepo 'gh-vmss-img-runners' `
>     -SubscriptionId '<TBD>' `
>     -OutputPath './Installation/.bootstrap-output.json'
> ```
>
> Output captured:
> - SP Client ID: `<TBD>`
> - SP Object ID: `<TBD>`
> - Tenant ID: `<TBD>`
>
> Anything noteworthy: _(filled in during execution)_

---

**Next step:** **[Step 2 — Deploy Azure prereqs](Step2-AzurePrereqs.md)**
