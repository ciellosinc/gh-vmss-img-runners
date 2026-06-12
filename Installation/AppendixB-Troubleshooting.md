# Appendix B — Troubleshooting

Failures grouped by which step they're most likely to surface at. If a symptom matches multiple steps, the listing under the EARLIEST step is the primary fix path.

---

## Step 1 — Bootstrap-Entra.ps1

### `az login` says you're signed in but `az ad sp create` fails with "Insufficient privileges"

The signed-in identity isn't an Application Administrator (or Cloud Application Administrator) in Entra. Subscription Owner ≠ Entra App Admin — they're independent grants.

**Fix**: Have someone with **Application Administrator** in Entra ID run Step 1, then they can leave. Steps 2-5 only need subscription RBAC.

### "Insufficient privileges" on `az role assignment create`

The signed-in identity isn't a subscription Owner. Contributor cannot assign User Access Administrator (UAA needs Owner to grant).

**Fix**: Get an Owner to run Step 1.

### `gh api -X PUT environments/<env>` returns 403

Your `gh` PAT doesn't have `admin:repo` scope (or equivalent permission via the org settings).

**Fix**: `gh auth refresh -s admin:repo,admin:org` and re-run.

### `gh api` returns 404 on the repo

Either the repo name is wrong, or your `gh` session is signed in to an account that doesn't have access to the repo.

**Fix**: `gh auth status` to confirm the account; check that the account is a member of the org with at least read access.

### Script crashes partway through (e.g. on FIC creation)

Re-run it. The script is idempotent — completed resources are detected as `[Exists]` and skipped.

### "Cannot find type 'SecureString'"

You're running Windows PowerShell 5.1, not PowerShell 7+.

**Fix**: `pwsh` not `powershell`. Install PowerShell 7+ from `https://aka.ms/install-powershell`.

---

## Step 2 — Deploy-to-Azure / ARM

### Storage account name "already exists" but you didn't create one

Storage account names are **globally unique** across all of Azure. The name you picked was taken (likely by someone else, somewhere else).

**Fix**: Pick a different name. The portal form's regex enforces 3-24 lowercase alphanumeric; add some entropy.

### `Microsoft.Storage` provider not registered

A fresh subscription might not have the Microsoft.Storage resource provider registered.

**Fix**:
```bash
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Resources
az provider register --namespace Microsoft.Authorization
```
Re-run the ARM deploy after registration completes (~1-2 min).

### ARM deploy succeeds but Step 4 says "RBAC: SP has Blob Data Contributor: MISSING"

You probably pasted the SP's **Client ID** instead of **Object ID**. They're different GUIDs for the same SP.

**Fix**: Look at Step 1's output again. The line labeled `SP Object ID (for ARM template input)` is what Step 2 needs. Re-run the ARM deploy with the correct value (it'll detect the role assignment already missing and add it).

### `MissingSubscription` error on `az` commands after sub-switching

Stale cached token. This is unrelated to anything you did wrong.

**Fix**: `az login --use-device-code` to refresh, then re-run the failing command unchanged. (See [memory note](../.claude/CLAUDE.md) on Az CLI cached-session rule.)

### ARM deploy fails with "Cannot perform the operation as the principal does not exist in the directory"

You pasted an SP Object ID that doesn't exist in the tenant the ARM deployment is targeting. Usually means you bootstrapped the SP in tenant A but are deploying ARM in tenant B.

**Fix**: Confirm `az account show --query tenantId` matches what Step 1 reported. If they differ, switch contexts: `az account set --subscription <correct-sub>`.

---

## Step 3 — Set-GitHubSecrets.ps1

### `gh secret set` returns 403

Your `gh` PAT doesn't have `admin:repo` (or your org has SAML SSO that hasn't been authorized).

**Fix**:
- Verify scope: `gh auth status --show-token`, then inspect the token's scopes in GitHub UI
- If SAML SSO: `gh auth refresh -s admin:repo --hostname github.com`, then visit the SSO authorization link the GitHub UI surfaces

### `Set-GitHubSecrets.ps1` finishes without errors but `gh secret list` doesn't show the new secrets

You're listing secrets on the wrong repo. The script targets `<your-org>/<your-repo>`; `gh secret list` without `--repo` lists secrets on whatever the local `gh` context defaults to.

**Fix**: `gh secret list --repo '<your-org>/<your-repo>' --json name`

### "Password does not meet complexity requirements" loop

Azure VMSS requires 12+ chars and 3 of {upper, lower, digit, special}. Common gotcha: the special character class doesn't include all the ones you might expect — stick to `!@#$%^&*` and you're safe.

**Fix**: Pick a stronger password that hits the three classes.

### Optional `GH_SECRETS_PAT` returns 403 mid-TF-apply

Your fine-grained PAT used as `GH_SECRETS_PAT` is missing the `Environments: Read and write` scope on the consumer repos. See memory note `project_gh_secrets_pat_permissions.md`.

**Fix**: Edit the PAT in the GitHub UI, add `Environments: R/W` on the consumer repos, re-run TF apply.

---

## Step 4 — Verify-Prereqs.ps1

### Exits with `[ABORT]` on pre-flight

Either `az` or `gh` isn't signed in. The abort message tells you which.

**Fix**: Run the suggested `az login` or `gh auth login`, then re-run Verify.

### "RBAC: SP has Blob Data Contributor: MISSING" but I see it in the portal

The portal shows the role assignment, but the SP Object ID in the role assignment is different from the SP Object ID you're verifying with.

**Fix**: Run `az role assignment list --scope <sa-id> --query '[].principalId' -o tsv` and check what principalId is actually on the SA. Compare to `az ad sp show --id <sp-client-id> --query id -o tsv`. Mismatch → re-run ARM with the right `spObjectId`.

### All FICs FAIL even though `Bootstrap-Entra.ps1` reported them as Created

The FIC subjects use the format `repo:<org>/<repo>:environment:<env>`. If the FIC was created with a different format (e.g. `:ref:refs/heads/main`), the subject won't match what `Verify-Prereqs.ps1` expects.

**Fix**: Delete the mismatched FICs (`az ad app federated-credential list --id <app-id>` to find them, then `... federated-credential delete ...`), then re-run `Bootstrap-Entra.ps1`.

---

## Step 5 — terraform-deploy.yml

### `terraform init` fails with "AuthorizationFailed" on the backend

The OIDC SP doesn't have Storage Blob Data Contributor on the SA, OR the AAD token isn't being passed correctly.

**Fix**: Re-run Verify-Prereqs.ps1 first; if it's green, the next likely cause is wrong `AZURE_SUBSCRIPTION_ID` secret (the SP is fine but it's looking at the wrong sub).

### `terraform plan` shows "no changes" but you expect resources

You're probably targeting a different environment than you think. Check `terraform-deploy.yml`'s input — the `environment` input determines which tfvars get loaded.

### `terraform apply` fails on a role assignment with "could not be created"

The SP has Contributor but not User Access Administrator. (Or it has both but the role propagation hasn't caught up — Azure RBAC takes a few minutes to fully propagate.)

**Fix**: Verify with Step 4. If Step 4 is green and you're still hitting this, wait 5 minutes and retry.

### Function app code never deploys after apply

The TF apply creates the Function App *shell*, not the code. Code comes from the consumer repos' deploy workflows.

**Fix**: Run the deploy workflow in `<your-org>/ScaleOutVmssFunction` and `<your-org>/ScaleInVmssFunction` to publish their code.

### VMSS never scales up when I trigger a workflow on a runner-target repo

Three likely causes, check in order:
1. **No image in the Compute Gallery** — run the `vm-runner-image` workflow at least once
2. **No webhook on the runner-target repo** — verify with `gh api repos/<runner-target-org>/<runner-target-repo>/hooks --jq '.[].config.url'`. Should include `https://func-scaleout-webhook-ghrunners-dev-cus.azurewebsites.net/api/webhook` (or your env's equivalent)
3. **ScaleOut function code not deployed** — check App Insights `traces` for any execution; if empty, the function isn't running

### Workflow shows OIDC auth failure: "No matching federated identity credential"

The FIC subject on the SP doesn't match what the workflow is presenting. Common causes:
- Workflow runs on a branch other than `main` (subject becomes `repo:.../ref:refs/heads/<branch>` instead of `environment:<env>`)
- The `environment:` block in the workflow yaml isn't set to one of the 6 expected environments

**Fix**: Either run the workflow on `main` with the right `environment:` field set, OR add an additional FIC subject pattern (`Bootstrap-Entra.ps1` can be extended).

---

## General

### "I lost the `.bootstrap-output.json` file"

You can regenerate the values:

```bash
# SP Client ID
az ad sp list --filter "displayName eq 'GitHub-OIDC-GHRunners-<your-org>'" --query '[0].appId' -o tsv

# SP Object ID
az ad sp list --filter "displayName eq 'GitHub-OIDC-GHRunners-<your-org>'" --query '[0].id' -o tsv

# Tenant ID
az account show --query tenantId -o tsv
```

Or just re-run `Bootstrap-Entra.ps1 -OutputPath ./Installation/.bootstrap-output.json` — it'll detect the SP exists and re-emit the values.

### "I want to start over from scratch"

```bash
# Delete the SP (this also removes its FICs and role assignments)
az ad sp delete --id <SP-Object-Id>
az ad app delete --id <App-Object-Id>

# Delete the state backend RG (DANGEROUS — destroys all Terraform state)
az group delete --name rg-terraform-state --yes --no-wait

# Delete the runtime RG (DANGEROUS — destroys all live infrastructure)
az group delete --name rg-ghrunners-dev-<region-short> --yes --no-wait

# Delete the GH environments (one per env)
for env in dev test prod dev-plan test-plan prod-plan; do
  gh api -X DELETE "repos/<org>/<repo>/environments/$env"
done

# Remove the GH secrets (one per name)
gh secret remove AZURE_CLIENT_ID --repo '<org>/<repo>'
# ... etc

# Remove the variable
gh variable delete TFSTATE_STORAGE_ACCOUNT --repo '<org>/<repo>'
```

Then run Steps 1-5 again from scratch.

---

If something here doesn't cover your case, capture the full error output and file it as a note under `.claude/Docs/Tracking/installation-friction/` for the next iteration.
