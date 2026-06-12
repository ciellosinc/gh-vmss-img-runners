<#
.SYNOPSIS
    Step 4 of the gh-vmss-img-runners installation flow — verify everything from Steps
    1-3 is in place before kicking off the first terraform-deploy.yml run.

.DESCRIPTION
    Read-only smoke check. Verifies the state left by Bootstrap-Entra.ps1 (Step 1), the
    ARM deploy (Step 2), and Set-GitHubSecrets.ps1 (Step 3). Exits 0 if everything green,
    non-zero with a structured failure list if anything is missing.

    Safe to run anytime, including after a `terraform apply` (it doesn't validate
    Terraform-owned resources — only the prereqs that Steps 1-3 own).

.PARAMETER GitHubOrg
    GitHub org owning the repo.

.PARAMETER GitHubRepo
    Repo name.

.PARAMETER SubscriptionId
    Azure subscription where Step 2 deployed the state backend.

.PARAMETER SpName
    Display name of the OIDC SP from Step 1.

.PARAMETER ResourceGroupName
    State backend resource group (default 'rg-terraform-state').

.PARAMETER StorageAccountName
    State backend storage account name from Step 2.

.PARAMETER ContainerName
    State backend blob container (default 'tfstate').

.PARAMETER Environments
    Expected GH environments + matching FIC subjects. Default matches what Step 1 created.

.PARAMETER InputPath
    Optional. Path to the Bootstrap-Entra.ps1 -OutputPath JSON. When provided, fills in
    SpName, GitHubOrg, GitHubRepo, SubscriptionId from the file (params override).

.EXAMPLE
    ./Verify-Prereqs.ps1 `
        -GitHubOrg 'gitspacecadet' `
        -GitHubRepo 'gh-vmss-img-runners' `
        -SubscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -SpName 'GitHub-OIDC-GHRunners-gitspacecadet' `
        -StorageAccountName 'sttfstate1234'

.NOTES
    Exit codes:
      0   all checks passed
      1   one or more checks failed
      2   pre-flight failure (CLI missing, not signed in, etc.)
#>

[CmdletBinding()]
param(
    [Parameter()] [string] $GitHubOrg,
    [Parameter()] [string] $GitHubRepo,
    [Parameter()] [string] $SubscriptionId,
    [Parameter()] [string] $SpName,
    [Parameter()] [string] $ResourceGroupName = 'rg-terraform-state',
    [Parameter()] [string] $StorageAccountName,
    [Parameter()] [string] $ContainerName = 'tfstate',
    [Parameter()] [string] $RuntimeLocation = 'centralus',
    [Parameter()] [string] $RuntimeRegionSuffix = 'cus',
    [Parameter()] [string[]] $Environments = @('dev', 'test', 'prod', 'dev-plan', 'test-plan', 'prod-plan'),
    [Parameter()] [string] $InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helpers

$script:Results = New-Object System.Collections.Generic.List[object]

function Format-Detail {
    <#
    .SYNOPSIS
        Returns one of two strings based on a condition.
    .DESCRIPTION
        Used to build [Add-Check] detail messages without inlining `(if ... else ...)` in
        parameter expressions — that pattern is PS 7+ only and brittle even there
        (parser sometimes treats the inner `if` as a cmdlet name, failing with
        'The term if is not recognized as a name of a cmdlet').
    #>
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TrueText,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $FalseText
    )
    if ($Condition) { return $TrueText } else { return $FalseText }
}

function Add-Check {
    param(
        [string] $Area,
        [string] $What,
        [bool] $Passed,
        [string] $Detail
    )
    $script:Results.Add([PSCustomObject] @{
        Area    = $Area
        Check   = $What
        Passed  = $Passed
        Detail  = $Detail
    })
    $marker = if ($Passed) { '[ OK  ]' } else { '[FAIL ]' }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    Write-Host ("{0} {1,-12} {2,-50} {3}" -f $marker, $Area, $What, $Detail) -ForegroundColor $color
}

function Write-SectionHeader {
    param([string] $Title)
    Write-Host ''
    Write-Host "----- $Title -----" -ForegroundColor Cyan
}

#endregion

#region Pre-flight

Write-Host ''
Write-Host '===== Verify-Prereqs =====' -ForegroundColor Cyan

foreach ($cmd in 'az', 'gh') {
    if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[ABORT] '$cmd' not found in PATH." -ForegroundColor Red
        exit 2
    }
}

# Load -InputPath defaults
if ($InputPath) {
    if (-not (Test-Path $InputPath)) {
        Write-Host "[ABORT] -InputPath '$InputPath' not found." -ForegroundColor Red
        exit 2
    }
    $bootstrap = Get-Content $InputPath -Raw | ConvertFrom-Json
    if (-not $GitHubOrg)      { $GitHubOrg      = $bootstrap.GitHubOrg }
    if (-not $GitHubRepo)     { $GitHubRepo     = $bootstrap.GitHubRepo }
    if (-not $SubscriptionId) { $SubscriptionId = $bootstrap.SubscriptionId }
    if (-not $SpName)         { $SpName         = $bootstrap.SpName }
}

foreach ($pair in @{ GitHubOrg = $GitHubOrg; GitHubRepo = $GitHubRepo; SubscriptionId = $SubscriptionId; SpName = $SpName; StorageAccountName = $StorageAccountName }.GetEnumerator()) {
    if (-not $pair.Value) {
        Write-Host ("[ABORT] -{0} is required (provide directly or via -InputPath)." -f $pair.Key) -ForegroundColor Red
        exit 2
    }
}

$azAccount = az account show 2>$null | ConvertFrom-Json
if (-not $azAccount) {
    Write-Host '[ABORT] az login required.' -ForegroundColor Red
    exit 2
}
if ($azAccount.id -ne $SubscriptionId) {
    az account set --subscription $SubscriptionId | Out-Null
}

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[ABORT] gh CLI not signed in.' -ForegroundColor Red
    exit 2
}

$repoSlug = "$GitHubOrg/$GitHubRepo"

#endregion

#region Entra checks (Step 1)

Write-SectionHeader 'Entra (Step 1)'

$sp = az ad sp list --filter "displayName eq '$SpName'" --query '[0]' -o json 2>$null | ConvertFrom-Json
if ($sp) {
    Add-Check -Area 'Entra' -What 'SP exists' -Passed $true -Detail $SpName
    $spObjectId = $sp.id
    $appObjectId = az ad app show --id $sp.appId --query 'id' -o tsv

    $subScope = "/subscriptions/$SubscriptionId"
    foreach ($role in @('Contributor', 'User Access Administrator')) {
        # Universal --assignee syntax for cross-version az CLI compatibility (Phase B fix)
        $hasRole = az role assignment list `
            --assignee $spObjectId `
            --role $role --scope $subScope `
            --query '[0].id' -o tsv 2>$null
        Add-Check -Area 'Entra' -What "Role: $role" -Passed ([bool]$hasRole) -Detail (Format-Detail ([bool]$hasRole) 'assigned at sub scope' 'MISSING — re-run Bootstrap-Entra.ps1')
    }

    $fics = az ad app federated-credential list --id $appObjectId -o json | ConvertFrom-Json
    foreach ($env in $Environments) {
        $expectedSubject = "repo:$GitHubOrg/$GitHubRepo`:environment:$env"
        $hasFic = [bool] ($fics | Where-Object { $_.subject -eq $expectedSubject })
        Add-Check -Area 'Entra' -What "FIC: env=$env" -Passed $hasFic -Detail (Format-Detail $hasFic $expectedSubject "MISSING subject '$expectedSubject'")
    }
} else {
    Add-Check -Area 'Entra' -What 'SP exists' -Passed $false -Detail "SP '$SpName' not found. Re-run Bootstrap-Entra.ps1."
}

# GH environments
foreach ($env in $Environments) {
    $envCheck = gh api "repos/$repoSlug/environments/$env" --jq '.name' 2>$null
    $exists = ($LASTEXITCODE -eq 0 -and [bool]$envCheck)
    Add-Check -Area 'GitHub' -What "Env: $env" -Passed $exists -Detail (Format-Detail $exists 'exists' 'MISSING — re-run Bootstrap-Entra.ps1')
}

#endregion

#region Azure prereqs (Step 2)

Write-SectionHeader 'Azure prereqs (Step 2)'

$rg = az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json
Add-Check -Area 'Azure' -What 'Resource group' -Passed ([bool]$rg) -Detail (Format-Detail ([bool]$rg) "$ResourceGroupName in $($rg.location)" "MISSING $ResourceGroupName — re-run ARM deploy")

if ($rg) {
    $sa = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    Add-Check -Area 'Azure' -What 'Storage account' -Passed ([bool]$sa) -Detail (Format-Detail ([bool]$sa) "$StorageAccountName" "MISSING $StorageAccountName")

    if ($sa) {
        # Container check — use AAD auth via az CLI
        $container = az storage container show `
            --account-name $StorageAccountName `
            --name $ContainerName `
            --auth-mode login 2>$null | ConvertFrom-Json
        Add-Check -Area 'Azure' -What 'Blob container' -Passed ([bool]$container) -Detail (Format-Detail ([bool]$container) $ContainerName "MISSING $ContainerName container")

        # RBAC: SP has Storage Blob Data Contributor on the SA
        if ($sp) {
            # Universal --assignee syntax for cross-version az CLI compatibility (Phase B fix)
            $hasBlobRole = az role assignment list `
                --assignee $sp.id `
                --role 'Storage Blob Data Contributor' `
                --scope $sa.id `
                --query '[0].id' -o tsv 2>$null
            Add-Check -Area 'Azure' -What 'RBAC: SP has Blob Data Contributor' -Passed ([bool]$hasBlobRole) -Detail (Format-Detail ([bool]$hasBlobRole) 'on storage account' 'MISSING — re-run ARM deploy or assign manually')
        }
    }
}

#endregion

#region GitHub secrets + variable (Step 3)

Write-SectionHeader 'GitHub secrets + variable (Step 3)'

$mandatorySecrets = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID', 'GH_PAT', 'VMSS_ADMIN_PASSWORD')
$optionalSecrets  = @('GH_SECRETS_PAT', 'GH_IMAGE_BUILDER_PAT', 'GH_ORGANIZATION')

# gh secret list returns names + updatedAt; we can't read values
$existingSecrets = gh secret list --repo $repoSlug --json name 2>$null | ConvertFrom-Json
$existingSecretNames = @($existingSecrets | ForEach-Object { $_.name })

foreach ($s in $mandatorySecrets) {
    $present = $existingSecretNames -contains $s
    Add-Check -Area 'GitHub' -What "Secret: $s" -Passed $present -Detail (Format-Detail $present 'set (value not readable)' 'MISSING — re-run Set-GitHubSecrets.ps1')
}

foreach ($s in $optionalSecrets) {
    $present = $existingSecretNames -contains $s
    if ($present) {
        Add-Check -Area 'GitHub' -What "Secret: $s" -Passed $true -Detail 'set (optional)'
    } else {
        # Optional — log info but don't count as fail
        Write-Host ("[ INFO] {0,-12} {1,-50} not set (optional)" -f 'GitHub', "Secret: $s") -ForegroundColor Gray
    }
}

$existingVars = gh variable list --repo $repoSlug --json name,value 2>$null | ConvertFrom-Json

$tfstateVar = $existingVars | Where-Object { $_.name -eq 'TFSTATE_STORAGE_ACCOUNT' }
if ($tfstateVar) {
    $valueMatches = ($tfstateVar.value -eq $StorageAccountName)
    Add-Check -Area 'GitHub' -What 'Variable: TFSTATE_STORAGE_ACCOUNT' -Passed $valueMatches -Detail (Format-Detail $valueMatches "matches '$StorageAccountName'" "value '$($tfstateVar.value)' != expected '$StorageAccountName'")
} else {
    Add-Check -Area 'GitHub' -What 'Variable: TFSTATE_STORAGE_ACCOUNT' -Passed $false -Detail 'MISSING — re-run Set-GitHubSecrets.ps1'
}

# TFSTATE_RESOURCE_GROUP_NAME variable — backs the parameterized resource_group_name in backend.tf
$rgVar = $existingVars | Where-Object { $_.name -eq 'TFSTATE_RESOURCE_GROUP_NAME' }
if ($rgVar) {
    $rgMatches = ($rgVar.value -eq $ResourceGroupName)
    Add-Check -Area 'GitHub' -What 'Variable: TFSTATE_RESOURCE_GROUP_NAME' -Passed $rgMatches -Detail (Format-Detail $rgMatches "matches '$ResourceGroupName'" "value '$($rgVar.value)' != expected '$ResourceGroupName'")
} else {
    Add-Check -Area 'GitHub' -What 'Variable: TFSTATE_RESOURCE_GROUP_NAME' -Passed $false -Detail 'MISSING — re-run Set-GitHubSecrets.ps1 (introduced in Phase B-fix #5)'
}

# TFSTATE_CONTAINER_NAME variable — backs the parameterized container_name in backend.tf
$containerVar = $existingVars | Where-Object { $_.name -eq 'TFSTATE_CONTAINER_NAME' }
if ($containerVar) {
    $containerMatches = ($containerVar.value -eq $ContainerName)
    Add-Check -Area 'GitHub' -What 'Variable: TFSTATE_CONTAINER_NAME' -Passed $containerMatches -Detail (Format-Detail $containerMatches "matches '$ContainerName'" "value '$($containerVar.value)' != expected '$ContainerName'")
} else {
    Add-Check -Area 'GitHub' -What 'Variable: TFSTATE_CONTAINER_NAME' -Passed $false -Detail 'MISSING — re-run Set-GitHubSecrets.ps1 (introduced in Phase B-fix #5)'
}

# RUNTIME_LOCATION variable — exported by the workflow as TF_VAR_location, picked up by Terraform
$locationVar = $existingVars | Where-Object { $_.name -eq 'RUNTIME_LOCATION' }
if ($locationVar) {
    $locationMatches = ($locationVar.value -eq $RuntimeLocation)
    Add-Check -Area 'GitHub' -What 'Variable: RUNTIME_LOCATION' -Passed $locationMatches -Detail (Format-Detail $locationMatches "matches '$RuntimeLocation'" "value '$($locationVar.value)' != expected '$RuntimeLocation'")
} else {
    Add-Check -Area 'GitHub' -What 'Variable: RUNTIME_LOCATION' -Passed $false -Detail 'MISSING — re-run Set-GitHubSecrets.ps1 (introduced in Phase B-fix #9)'
}

# RUNTIME_REGION_SUFFIX variable — exported as TF_VAR_region; drives the suffix in runtime resource names
$regionVar = $existingVars | Where-Object { $_.name -eq 'RUNTIME_REGION_SUFFIX' }
if ($regionVar) {
    $regionMatches = ($regionVar.value -eq $RuntimeRegionSuffix)
    Add-Check -Area 'GitHub' -What 'Variable: RUNTIME_REGION_SUFFIX' -Passed $regionMatches -Detail (Format-Detail $regionMatches "matches '$RuntimeRegionSuffix'" "value '$($regionVar.value)' != expected '$RuntimeRegionSuffix'")
} else {
    Add-Check -Area 'GitHub' -What 'Variable: RUNTIME_REGION_SUFFIX' -Passed $false -Detail 'MISSING — re-run Set-GitHubSecrets.ps1 (introduced in Phase B-fix #9)'
}

#endregion

#region Summary

Write-SectionHeader 'Summary'

$passed = @($script:Results | Where-Object { $_.Passed }).Count
$failed = @($script:Results | Where-Object { -not $_.Passed }).Count
$total  = $script:Results.Count

$summaryColor = if ($failed -eq 0) { 'Green' } else { 'Yellow' }
Write-Host ("  Passed: {0} / {1}" -f $passed, $total) -ForegroundColor $summaryColor
if ($failed -gt 0) {
    Write-Host "  Failed: $failed" -ForegroundColor Red
    Write-Host ''
    Write-Host 'Failures:' -ForegroundColor Red
    $script:Results | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host ("    - [{0}] {1}: {2}" -f $_.Area, $_.Check, $_.Detail) -ForegroundColor Red
    }
    Write-Host ''
    Write-Host 'Fix the failures, then re-run Verify-Prereqs.ps1.' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host 'All checks green. Ready for Step 5 — dispatch terraform-deploy.yml.' -ForegroundColor Green
exit 0

#endregion
