# Appendix A — GitHub App auth (alternative to PAT)

The primary install flow ([Step 3](Step3-GitHubSecrets.md)) uses a **fine-grained Personal Access Token** as `GH_PAT`. This appendix covers the alternative: a **GitHub App** for runner registration.

---

## When to use a GitHub App instead of a PAT

| If… | Recommended |
|---|---|
| You're installing for personal/small-team use | **PAT** (simpler, fewer moving parts) |
| You need rate limit headroom (>5k req/hour) | GitHub App (15k req/hour per installation) |
| You need to avoid tying access to a single human's GitHub account | GitHub App (auth identity isn't a user) |
| You need fine-grained per-repo access control without listing every repo on a PAT | GitHub App (install on selected repos via UI) |
| You want PAT-rotation events to NOT impact runner registration | GitHub App (no rotation cadence imposed) |

If none of the above apply, **stay with PAT**. The PAT path is what the worked examples and most of the team operate on day-to-day.

---

## What changes vs the PAT flow

| Aspect | PAT flow | GitHub App flow |
|---|---|---|
| Secret in Key Vault | `github-pat` | `github-private-key` (PEM) |
| Mandatory GH repo secrets | `GH_PAT` | `GH_APP_ID`, `GH_INSTALLATION_ID`, `GH_APP_PRIVATE_KEY` (no `GH_PAT` required) |
| TF auth strategy variable | `auth_strategy = "PAT"` (default) | `auth_strategy = "GitHubApp"` |
| Runner registration script (CSE) | reads `GH_PAT` from KV, hits org `/runners/registration-token` | reads private key from KV, generates JWT, exchanges for installation token, then hits the same registration endpoint |
| Identity in webhook logs | shows as the PAT owner's user | shows as the App |

Steps 1, 2, 4, 5 are **identical**. Only Step 3 and the TF config change.

---

## Pre-app setup

You need to create the GitHub App **before** running `Set-GitHubSecrets.ps1`. This is a manual one-time step in the GitHub UI:

1. Go to `https://github.com/organizations/<your-org>/settings/apps` (or your user account's Developer settings if not using an org)
2. Click **New GitHub App**
3. Required settings:
   - **App name**: `<your-org>-gh-vmss-runners` (must be globally unique)
   - **Homepage URL**: link to your repo
   - **Webhook**: **Uncheck** "Active" — this App is for registration only, not webhooks
   - **Permissions** → **Repository permissions**:
     - **Actions**: Read and write (for ScaleIn janitor)
     - **Administration**: Read and write (for self-hosted runner registration on individual repos)
     - **Metadata**: Read
     - **Contents**: Read (for release lookups)
   - **Permissions** → **Organization permissions**:
     - **Self-hosted runners**: Read and write (for org-level runner registration)
   - **Where can this GitHub App be installed?**: Only on this account
4. Click **Create GitHub App**
5. On the App detail page:
   - Copy the **App ID** (top of the page) → this becomes `GH_APP_ID`
   - Scroll to **Private keys** → click **Generate a private key** → save the `.pem` file → its **contents** become `GH_APP_PRIVATE_KEY`
6. Install the App on the runner-target repos:
   - Click **Install App** in the left sidebar
   - Click **Install** next to your org
   - Choose **All repositories** or **Only select repositories** as appropriate
   - After install, copy the **Installation ID** from the URL (the trailing number) → this becomes `GH_INSTALLATION_ID`

---

## Modified Step 3 — Set the App secrets

```pwsh
$appId = '<your-app-id>'
$installationId = '<your-installation-id>'
$privateKey = Get-Content '<path-to-pem-file>' -Raw

./Installation/scripts/Set-GitHubSecrets.ps1 `
    -GitHubOrg '<your-org>' `
    -GitHubRepo '<your-repo>' `
    -SubscriptionId '<your-sub-id>' `
    -StorageAccountName '<from-step-2>' `
    -InputPath './Installation/.bootstrap-output.json'

# Then set the App-specific secrets manually
gh secret set GH_APP_ID --repo '<your-org>/<your-repo>' --body $appId
gh secret set GH_INSTALLATION_ID --repo '<your-org>/<your-repo>' --body $installationId
gh secret set GH_APP_PRIVATE_KEY --repo '<your-org>/<your-repo>' --body $privateKey
```

`Set-GitHubSecrets.ps1` will still prompt for `GH_PAT` and `VMSS_ADMIN_PASSWORD`. For `GH_PAT`, you can supply a minimal-scope PAT (just for release lookups) or skip it — TF uses the App for runner registration regardless of `GH_PAT`'s scope.

---

## TF variable change

In your `terraform/environments/dev.tfvars` (or wherever you keep env-specific overrides):

```hcl
auth_strategy = "GitHubApp"
```

The default is `"PAT"`. Setting `"GitHubApp"` tells TF to:
1. Write `github-private-key` to Key Vault from `GH_APP_PRIVATE_KEY` instead of `github-pat` from `GH_PAT`
2. Configure `Initialize-GhRunner.ps1` to use the JWT exchange flow

---

## Switching from PAT to GitHub App on a running install

1. Create the App and capture `App ID`, `Installation ID`, private key (see above)
2. Set the 3 new repo secrets
3. Change `auth_strategy = "GitHubApp"` in your env tfvars
4. Run `terraform-deploy.yml` → apply will replace the KV secret + update VMSS CSE config
5. **Roll the VMSS** so existing instances re-run CSE with the new auth: `az vmss update-instances --resource-group <rg> --name <vmss> --instance-ids '*'`

Existing in-flight workflow jobs complete with the OLD runner auth (PAT) — that's fine. New instances boot with the App.

---

## Switching back from GitHub App to PAT

Reverse:
1. Ensure `GH_PAT` is set on the repo (you may have set it as a fallback during Step 3 anyway)
2. Set `auth_strategy = "PAT"`
3. Run `terraform-deploy.yml`
4. Roll the VMSS

The GitHub App can stay installed; it just goes unused.

---

## Notes

- The App's private key is **as sensitive as a PAT** — protect it the same way.
- Rotate the private key by generating a new one in the App settings, updating `GH_APP_PRIVATE_KEY`, re-running TF apply, and rolling the VMSS. The old key can be deleted from the App settings after rollout.
- A GitHub App has **higher rate limits** than a PAT (15k req/hour vs 5k) but the same fundamental API. If you're routinely hitting rate limits with a PAT and your runner volume is growing, switching to an App is the right call.
