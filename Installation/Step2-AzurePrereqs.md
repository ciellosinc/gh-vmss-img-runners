# Step 2 — Deploy the Azure prereqs (Terraform state backend)

> **Performed by:** Azure Subscription Owner (or anyone with Contributor + User Access Administrator on the sub)

---

## What you'll need

| Item | Where from |
|---|---|
| Service Principal **Object ID** | Step 1 output (the `SP Object ID` line) |
| Azure subscription | Same one Step 1 ran in |
| A globally unique storage account name (3–24 lowercase alphanumeric) | Pick one — the portal form will suggest a default |

---

## What this step creates

| Resource | Name (default) | Purpose |
|---|---|---|
| Resource Group | `rg-terraform-state` | Hosts the state storage account |
| Storage Account | `<your-choice>` (3–24 chars, globally unique) | Holds Terraform state blobs |
| Blob Container | `tfstate` | Container that `terraform-deploy.yml` writes to |
| Role Assignment | Storage Blob Data Contributor → your Step 1 SP | Lets the SP read/write state via AAD auth |

The defaults match what [`terraform/backend.tf`](../terraform/backend.tf) expects. Override at your peril.

---

## Instructions

### 2.1 — Option A: Click the "Deploy to Azure" button (recommended)

From the repo root `README.md`, click the **Deploy to Azure** badge. The Azure Portal opens a custom form (driven by `createUiDefinition.json`) that asks for:

1. **Region** — pick your preferred Azure region
2. **Service Principal Object ID** — paste the value from Step 1
3. **Resource group name** — leave as `rg-terraform-state` unless you have a naming convention requiring otherwise
4. **Storage account name** — pick a globally unique value (3–24 lowercase alphanumeric)
5. **Container name** — leave as `tfstate`

Click **Review + create**, then **Create**. Deployment completes in 1–2 minutes.

### 2.2 — Option B: Run from the CLI (alternative if you prefer)

```bash
# From the repo root
az deployment sub create \
  --location <your-region> \
  --template-file ./Installation/prereqs/azuredeploy.json \
  --parameters spObjectId='<paste-from-step-1>' \
               storageAccountName='<your-unique-name>'
```

The CLI path is useful for scripted installs or when you want to run from a CI context that already has an Azure session.

> **Why `allowSharedKeyAccess: false` and `defaultToOAuthAuthentication: true`:** the state backend uses **Azure AD authentication** (`use_azuread_auth = true` in `backend.tf`). Storage account keys are not used and not needed; disabling them removes the largest credential exfiltration surface on the SA.

> **Why subscription-scope deployment:** the ARM template creates the resource group itself. A resource-group-scope template would require the operator to create the RG first as a manual step. Subscription scope makes the "click one button → it works" UX possible.

### 2.3 — Capture the output

After deployment, check the **Outputs** tab on the deployment page:

```
storageAccountName : <your-unique-name>
resourceGroupName  : rg-terraform-state
containerName      : tfstate
tfBackendConfig    : { resource_group_name: ..., storage_account_name: ..., ... }
```

You'll pass the `storageAccountName` value to Step 3 (as `-StorageAccountName`).

---

## What's NOT in this step (and why)

| Resource | Why it's not here | Where it comes from |
|---|---|---|
| Key Vault | TF creates it | `terraform/modules/foundation/key-vault.tf` — Step 5 |
| Log Analytics workspace | TF creates it | `terraform/modules/foundation/log-analytics.tf` — Step 5 |
| Application Insights | TF creates it | `terraform/modules/runtime/monitoring.tf` — Step 5 |
| VMSS / Function Apps / VNet | TF creates them | `terraform/modules/runtime/*.tf` — Step 5 |
| RBAC role assignments on the runtime resources | TF creates them | `terraform/modules/runtime/role-assignments.tf` — Step 5 |

**Step 2's ARM template is deliberately minimal.** Anything TF can create, TF creates. Duplicating these in ARM would force name collisions and state-import headaches on every re-install.

---

## Verify before continuing

```bash
# Resource group exists
az group show --name rg-terraform-state --query 'properties.provisioningState' -o tsv
# Expected: Succeeded

# Storage account + container exist
az storage account show --name '<your-unique-name>' --query '{name:name, location:location}'
az storage container show --account-name '<your-unique-name>' --name tfstate --auth-mode login --query 'name' -o tsv
# Expected: tfstate

# SP has Blob Data Contributor on the SA
az role assignment list \
  --assignee '<sp-object-id-from-step-1>' \
  --scope $(az storage account show -n '<your-unique-name>' --query id -o tsv) \
  --query '[].roleDefinitionName' -o tsv
# Expected: Storage Blob Data Contributor
```

Or run [Step 4 — `Verify-Prereqs.ps1`](Step4-Verify.md).

---

## Worked example (placeholder — filled in during the live switch)

> **Worked example — `<YYYY-MM-DD>` install on `<new-org>` / `<new-sub>`**
>
> Portal form values:
> - Region: `<TBD>`
> - SP Object ID: `<TBD>` (from Step 1)
> - Resource group: `rg-terraform-state`
> - Storage account: `<TBD>`
> - Container: `tfstate`
>
> Deployment duration: `<TBD>`
> Anything noteworthy: _(filled in during execution)_

---

**Next step:** **[Step 3 — Set GitHub secrets + variable](Step3-GitHubSecrets.md)**
