# Scenarios

Self-contained how-to guides for specific operations on the gh-vmss-img-runners stack.

If [`Installation/`](../Installation/README.md) is the **first-time setup path** ("how do I stand this up from zero?"), `Scenarios/` is the **ongoing operations playbook** ("how do I do *X* once it's running?").

Each scenario file is independent — read just the one you need.

Inspired by [`microsoft/AL-Go/Scenarios`](https://github.com/microsoft/AL-Go/tree/main/Scenarios)'s structure.

---

## When to use Scenarios vs. Installation

| Goal | Where to go |
|---|---|
| Fresh install on a new Azure sub + new GitHub org | [Installation/README.md](../Installation/README.md) |
| Verifying an existing install | [Installation/Step4-Verify.md](../Installation/Step4-Verify.md) |
| One specific operation (create a PAT, rotate a credential, etc.) | This folder |
| Troubleshooting a known failure mode | [Installation/AppendixB-Troubleshooting.md](../Installation/AppendixB-Troubleshooting.md) |

---

## Available scenarios

| Scenario | Performed by | Cross-links |
|---|---|---|
| [`Create-GhPat.md`](Create-GhPat.md) | GitHub user with permission to mint org-scoped PATs | Referenced from [Step3-GitHubSecrets](../Installation/Step3-GitHubSecrets.md) |

---

## Scenarios backlog (Phase C — to land after Phase B finishes)

These came out of Phase B live-walk friction or follow-up patterns we already understand and want to codify:

| Planned scenario | Triggered by |
|---|---|
| `Prepare-TargetRepo.md` | The "create your fork or fresh repo on the new org" prep step (precedes Installation Step 1) |
| `Switch-AzureSubscription.md` | Migrating the stack from one Azure sub to another (TF state backend move + secret rotation + FIC re-federation) |
| `Make-RepoPublic-ForDeployToAzure.md` | The Deploy-to-Azure badge requires a public repo for `raw.githubusercontent.com` access |
| `Customize-BackendNames.md` | When you don't want the default `rg-terraform-state` / `tfstate` and need to flow custom names through the workflows |
| `Rotate-OidcSp.md` | Rotating the SP that the GH-Actions workflows authenticate as |
| `Add-RunnerTargetRepo.md` | Adding a new repo whose CI/CD jobs should run on the VMSS (PAT scope expansion + webhook config) |
| `Switch-PatToGitHubApp.md` | Moving from PAT-based runner registration to a GitHub App ([see Installation/AppendixA](../Installation/AppendixA-GitHubAppAuth.md) for the conceptual delta) |
| `Recover-FromBadSpIdInArmTemplate.md` | Cleanup when the wrong identifier (Client ID vs Object ID) got into a role assignment |
| `Teardown-And-StartOver.md` | Full clean-slate teardown when you want to re-run install from zero |

Each will be its own focused doc following the same skeleton as `Create-GhPat.md`.

---

## Scenario doc skeleton

Every scenario file follows this shape (matches the Installation Step files for consistency):

```markdown
# Scenario — <verb>-<noun>

> **Performed by:** <role>
> **Frequency:** <one-shot | annual | per-incident | on-demand>
> **Prerequisites:** <what must already be in place>

## What this does
(one or two sentences)

## Steps
1. ...
2. ...

## Verify
(how to confirm the scenario succeeded)

## Cross-references
- Where this is referenced from in Installation/ or other Scenarios/
- Related memories or design notes
```

---

## Contributing a new scenario

Open a PR with:
1. A new `Scenarios/<Verb-Noun>.md` file following the skeleton above
2. A row added to the **Available scenarios** table above
3. Cross-link added from the Installation step (or other scenario) where the new doc is most useful
