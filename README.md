# gh-vmss-img-runners

GitHub self-hosted runners on Azure Virtual Machine Scale Sets — provisioned by Terraform, fronted by two Function Apps (auto-scaling), and built from a Packer-baked Windows Server 2022 image.

[![Deploy state backend to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitspacecadet%2Fgh-vmss-img-runners%2Fmain%2FInstallation%2Fprereqs%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitspacecadet%2Fgh-vmss-img-runners%2Fmain%2FInstallation%2Fprereqs%2FcreateUiDefinition.json)

> The button above kicks off **Step 2** of the install flow. **Start with [Step 1](Installation/Step1-EntraBootstrap.md)** — it creates the OIDC service principal that Step 2 needs.

---

## What this gives you

- A **Virtual Machine Scale Set** of Windows Server 2022 self-hosted runners that starts at **0 instances** (no idle cost)
- A **ScaleOut Function App** that responds to GitHub webhook events and adds capacity on demand
- A **ScaleIn Function App** that reaps idle runners on a timer + a janitor that catches stuck instances
- A **Packer image-builder pipeline** that re-bakes the runner image on a cadence you choose
- A **Key Vault** holding the runner registration PAT (or GitHub App private key); managed identities for everything else
- **OIDC authentication** end-to-end — no Azure service principal secrets in GitHub

---

## Install

**One-time setup**, ~20–40 minutes if you have the right permissions in hand:

→ **[Start with `Installation/README.md`](Installation/README.md)**

The install is 5 steps:
1. Bootstrap the Entra side (`Bootstrap-Entra.ps1`) — OIDC SP + roles + FICs + GH environments
2. Deploy the Azure prereqs (the "Deploy to Azure" button above) — Terraform state backend
3. Seed GitHub secrets + variable (`Set-GitHubSecrets.ps1`)
4. Verify (`Verify-Prereqs.ps1`)
5. Dispatch the first `terraform-deploy.yml` run

---

## After install — ongoing operations

| Reference | What's in it |
|---|---|
| [`terraform/README.md`](terraform/README.md) | Terraform module structure, environments, variables, what each module owns |
| [`Scripts/README.md`](Scripts/README.md) | Operational PowerShell scripts (webhook wiring, sub migrations, etc.) |

---

## Architecture (one-paragraph)

GitHub webhook → ScaleOut Function App → `VMSS.update --capacity +1` → new VM boots → Custom Script Extension runs `Initialize-GhRunner.ps1` → runner registers against the GitHub org (using PAT from Key Vault by default, or GitHub App via [Appendix A](Installation/AppendixA-GitHubAppAuth.md)) → workflow job assigns to the new runner → after completion, ScaleIn Function App marks the VM idle → janitor reaps after `POOL_TTL_MINUTES`. State lives in `VmssScaleTracking` (table storage); telemetry lives in Application Insights + the consumer-repo `.claude/` doc sets.

---

## Repository status

- **Canonical deployment path**: Terraform (this branch's `terraform/` directory)
- **Active sibling agent repos**: `<your-org>/ScaleInVmssFunction`, `<your-org>/ScaleOutVmssFunction`, `<your-org>/vm-runner-image`

---

## Note for forkers

The Deploy-to-Azure badge above points at the canonical `gitspacecadet/gh-vmss-img-runners` raw URLs. If you fork this repo to your own org, update the badge URL in this file to point at your fork — otherwise the button deploys *our* template, not yours. Find/replace `gitspacecadet/gh-vmss-img-runners` → `<your-org>/<your-fork-name>` and bump the branch name if you're working on something other than `main`.
