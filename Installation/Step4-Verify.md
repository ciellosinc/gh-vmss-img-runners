# Step 4 — Verify prereqs

> **Performed by:** Anyone (read-only)

This step is your **idempotency checkpoint**. It catches anything Steps 1-3 missed before Step 5 wastes time on a guaranteed-to-fail Terraform run.

---

## What you'll need

The same inputs from Steps 1-3, or just the JSON path if you used `-OutputPath`:

```pwsh
./Installation/scripts/Verify-Prereqs.ps1 `
    -GitHubOrg '<your-github-org>' `
    -GitHubRepo '<your-repo-name>' `
    -SubscriptionId '<your-sub-id>' `
    -SpName 'GitHub-OIDC-GHRunners-<your-org>' `
    -StorageAccountName '<from-step-2>' `
    -InputPath './Installation/.bootstrap-output.json'
```

If `-InputPath` is provided, `-GitHubOrg`, `-GitHubRepo`, `-SubscriptionId`, `-SpName` are read from the JSON (params still override).

---

## What this step creates

**Nothing.** It's read-only.

---

## What it checks

Grouped by Step:

### Step 1 (Entra)
- Service principal `<SpName>` exists
- SP has Contributor at subscription scope
- SP has User Access Administrator at subscription scope
- 6 GitHub environments exist on the repo
- 6 federated identity credentials exist on the SP with the right subjects

### Step 2 (Azure prereqs)
- Resource group `rg-terraform-state` exists
- Storage account `<StorageAccountName>` exists
- Container `tfstate` exists
- SP has **Storage Blob Data Contributor** on the storage account

### Step 3 (GitHub)
- 5 mandatory secrets present (names only — values aren't readable via API)
- 3 optional secrets reported (informational, not counted as failures)
- Variable `TFSTATE_STORAGE_ACCOUNT` set and matches `<StorageAccountName>`

---

## What the output looks like

### All green
```
===== Verify-Prereqs =====

----- Entra (Step 1) -----
[ OK  ] Entra        SP exists                                          GitHub-OIDC-GHRunners-<org>
[ OK  ] Entra        Role: Contributor                                  assigned at sub scope
[ OK  ] Entra        Role: User Access Administrator                    assigned at sub scope
[ OK  ] Entra        FIC: env=dev                                       repo:<org>/<repo>:environment:dev
... (6 FICs + 6 envs)

----- Azure prereqs (Step 2) -----
[ OK  ] Azure        Resource group                                     rg-terraform-state in centralus
[ OK  ] Azure        Storage account                                    sttfstate1234
[ OK  ] Azure        Blob container                                     tfstate
[ OK  ] Azure        RBAC: SP has Blob Data Contributor                 on storage account

----- GitHub secrets + variable (Step 3) -----
[ OK  ] GitHub       Secret: AZURE_CLIENT_ID                            set (value not readable)
... (5 mandatory + 3 optional)
[ OK  ] GitHub       Variable: TFSTATE_STORAGE_ACCOUNT                  matches 'sttfstate1234'

----- Summary -----
  Passed: 20 / 20

All checks green. Ready for Step 5 — dispatch terraform-deploy.yml.
```

Exits **0** on success.

### Something failed
```
[FAIL ] Entra        FIC: env=test                                      MISSING subject 'repo:<org>/<repo>:environment:test'
[FAIL ] Azure        RBAC: SP has Blob Data Contributor                 MISSING — re-run ARM deploy or assign manually

----- Summary -----
  Passed: 18 / 20
  Failed: 2

Failures:
    - [Entra] FIC: env=test: MISSING subject 'repo:<org>/<repo>:environment:test'
    - [Azure] RBAC: SP has Blob Data Contributor: MISSING — re-run ARM deploy or assign manually

Fix the failures, then re-run Verify-Prereqs.ps1.
```

Exits **1**. Don't proceed to Step 5 until this is zero.

---

## Common failures and fixes

| Failure | Most likely cause | Fix |
|---|---|---|
| `SP exists` FAIL | Wrong `-SpName` or Step 1 didn't run | Re-check the SP name; re-run `Bootstrap-Entra.ps1` |
| `Role: Contributor` FAIL | You ran Step 1 without Owner permissions | Get an Owner to re-run Step 1, or assign manually |
| `Role: User Access Administrator` FAIL | Same — needs Owner | Same |
| `FIC: env=<x>` FAIL | Environment didn't exist when FIC was created | Re-run `Bootstrap-Entra.ps1` (idempotent — will fill the gap) |
| `Resource group` FAIL | Step 2 ARM deploy never ran or failed | Re-run the Deploy-to-Azure button (or `az deployment sub create`) |
| `Storage account` FAIL | Wrong name parameter | Check the ARM deployment Outputs; pass the correct `-StorageAccountName` |
| `RBAC: Blob Data Contributor` FAIL | SP Object ID was wrong when ARM deployed | Re-run ARM with the correct `spObjectId`, OR assign manually: `az role assignment create --assignee <sp> --role 'Storage Blob Data Contributor' --scope <sa-resource-id>` |
| `Secret: <name>` FAIL | Step 3 script didn't include this secret | Re-run `Set-GitHubSecrets.ps1` with appropriate params |
| `Variable: TFSTATE_STORAGE_ACCOUNT` "mismatch" | You changed storage account names between Step 2 and Step 3 | Re-run `Set-GitHubSecrets.ps1 -StorageAccountName <correct-value>` |

For deeper troubleshooting, see [Appendix B — Troubleshooting](AppendixB-Troubleshooting.md).

---

## Worked example (placeholder — filled in during the live switch)

> **Worked example — `<YYYY-MM-DD>` install on `<new-org>` / `<new-sub>`**
>
> Command run:
> ```pwsh
> ./Installation/scripts/Verify-Prereqs.ps1 `
>     -InputPath './Installation/.bootstrap-output.json' `
>     -StorageAccountName '<TBD>'
> ```
>
> Result: `<TBD>` passed / `<TBD>` failed
> Anything noteworthy: _(filled in during execution)_

---

**Next step:** **[Step 5 — First deploy](Step5-FirstDeploy.md)**
