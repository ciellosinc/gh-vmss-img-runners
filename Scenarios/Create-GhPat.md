# Scenario — Create the `GH_PAT` fine-grained PAT

> **Performed by:** GitHub user with permission to mint org-scoped fine-grained PATs (typically org admin, or any org member if the org allows fine-grained PATs without approval).
> **Frequency:** Once per install + on PAT expiration (typically annual) + when adding new runner-target repos to scope.
> **Prerequisites:** GitHub account signed in; you know your runner-target organization name (e.g. `ciellosinc`).

---

## What this does

Creates a fine-grained Personal Access Token with the exact scopes the gh-vmss-img-runners stack needs to:

1. Register VMSS instances as self-hosted runners on the GitHub org
2. Read VMSS image releases from the `terraform-deploy.yml` workflow
3. Allow the ScaleIn janitor to query workflow-run state for stuck-VM detection

The PAT value then gets stored as the `GH_PAT` repo secret in [Installation Step 3](../Installation/Step3-GitHubSecrets.md).

---

## Steps

### 1. Navigate to the PAT creation page

<https://github.com/settings/personal-access-tokens/new>

### 2. Fill in the basics

| Field | Value |
|---|---|
| **Token name** | Descriptive, e.g. `<your-org>-ghvmss-runner-pat` (matches the operator's naming convention; visible to org admin in audit logs) |
| **Description** *(optional)* | "Runner registration + ScaleIn janitor for gh-vmss-img-runners" |
| **Resource owner** | Your organization (e.g. `ciellosinc`). If your org isn't in the dropdown, the org has not enabled fine-grained PATs — ask org admin to enable in Settings → Personal access tokens → "Allow access via fine-grained personal access tokens" |
| **Expiration** | 1 year is typical. Set a calendar reminder for renewal — you'll need to repeat this scenario at expiry. |

### 3. Repository access

Pick one:

| Option | When |
|---|---|
| **Only select repositories** → add `<your-org>/gh-vmss-img-runners` (and any runner-target repos you already know about) | Recommended initial install. Smallest blast radius. You'll edit the PAT to add more repos as you onboard them. |
| **All repositories** | Easiest for steady-state once you have many runner-target repos. Blast radius = every repo in the org. |
| **Public repositories** | NOT enough — the gh-vmss-img-runners repo is private by default and the PAT needs write access. |

### 4. Repository permissions

Click **Add permissions** or expand the Repository permissions section, then set:

| Permission | Access | Why |
|---|---|---|
| **Actions** | Read and write | ScaleIn janitor queries `actions/runs` for stuck-VM detection |
| **Contents** | Read | `terraform-deploy.yml` does release-lookup for VMSS image versions |
| **Metadata** | Read | Auto-required when any other repo permission is set; you may see this turn on automatically |

### 5. Organization permissions

Scroll further down. Set:

| Permission | Access | Why |
|---|---|---|
| **Self-hosted runners** | Read and write | Register/deregister VMSS runners on the org |
| **Administration** | Read and write | List runners + remove orphans during reconciliation |

### 6. Generate the token

Click **Generate token**. GitHub shows the PAT value **exactly once**. **Copy it immediately** to a secure clipboard manager or directly into the next step's prompt.

If you lose the value before storing it, you must regenerate (returns to Step 1).

### 7. Hand off to Installation Step 3

Continue with [`Installation/Step3-GitHubSecrets.md § 3.1`](../Installation/Step3-GitHubSecrets.md#31--run-the-script) — when `Set-GitHubSecrets.ps1` prompts for `GH_PAT`, paste the value. The input is masked (PowerShell `SecureString`).

---

## Verify

After [`Set-GitHubSecrets.ps1`](../Installation/scripts/Set-GitHubSecrets.ps1) completes, the secret is set on the repo. You cannot read the value back via API (GitHub security), but you can confirm the name exists:

```powershell
gh secret list --repo '<your-org>/gh-vmss-img-runners' --json name --jq '.[] | select(.name=="GH_PAT")'
# Expected: { "name": "GH_PAT" }
```

The PAT's actual scope correctness only gets exercised when the workflows run (Step 5) or when runners register at boot. To verify scopes against GitHub:

```bash
# Probe runner registration scope (org-level)
curl -sH "Authorization: Bearer <paste-pat-here>" \
     https://api.github.com/orgs/<your-org>/actions/runners/registration-token \
     -X POST -o /dev/null -w "HTTP %{http_code}\n"
# Expected: HTTP 201 (Created — the registration token endpoint)

# Probe actions:read on the runner repo
curl -sH "Authorization: Bearer <paste-pat-here>" \
     https://api.github.com/repos/<your-org>/gh-vmss-img-runners/actions/runs?per_page=1 \
     -o /dev/null -w "HTTP %{http_code}\n"
# Expected: HTTP 200
```

If either returns 401/403, the scope is missing and you need to edit the PAT to add it.

---

## When to redo this scenario

| Trigger | Action |
|---|---|
| **Expiration approaching** | Re-run this scenario to generate a fresh PAT; update `GH_PAT` secret via [`Set-GitHubSecrets.ps1`](../Installation/scripts/Set-GitHubSecrets.ps1) (or directly with `gh secret set GH_PAT --body <new-value> --repo <...>`) |
| **Adding a runner-target repo** | Edit the existing PAT at <https://github.com/settings/personal-access-tokens>, add the new repo to the access list. No new PAT needed. |
| **Removing a runner-target repo** | Same — edit and remove. |
| **Scope leak / accidentally committed value** | Revoke at <https://github.com/settings/personal-access-tokens>, run this scenario to mint a new PAT, update the secret. |

---

## Cross-references

- **Used from**: [`Installation/Step3-GitHubSecrets.md`](../Installation/Step3-GitHubSecrets.md) § 3.3
- **Related auth path**: [`Installation/AppendixA-GitHubAppAuth.md`](../Installation/AppendixA-GitHubAppAuth.md) (alternative — GitHub App instead of PAT)
- **Related scenarios** (Phase C):
  - `Add-RunnerTargetRepo.md` (when you have a new repo to scope the PAT to)
  - `Switch-PatToGitHubApp.md` (when PAT operationally hurts more than helps)
