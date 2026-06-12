<#
.SYNOPSIS
    Step 3 of the gh-vmss-img-runners installation flow — seed the GitHub repo secrets
    and variables that the terraform-deploy / terraform-ci workflows expect.

.DESCRIPTION
    Sets the 5 mandatory repo-level secrets, 3 optional repo-level secrets, and 1 repo
    variable that the workflows in .github/workflows/ consume.

    Mandatory (workflow fails without these):
      AZURE_CLIENT_ID         OIDC SP client ID   (from Step 1 output)
      AZURE_TENANT_ID         OIDC tenant         (from Step 1 output / az session)
      AZURE_SUBSCRIPTION_ID   Target Azure sub    (param)
      GH_PAT                  PAT for runner registration + release lookups
      VMSS_ADMIN_PASSWORD     VMSS admin password (TF_VAR_vmss_admin_password)

    Optional (warning if not set; some flows still work):
      GH_SECRETS_PAT          PAT for TF auto-syncing env secrets to consumer repos
      GH_IMAGE_BUILDER_PAT    PAT for TF auto-syncing secrets to vm-runner-image repo
      GH_ORGANIZATION         Target org for runner registration (often the same as
                              -GitHubOrg, but customers running runners in a different
                              org need to override)

    Repo variable (not secret):
      TFSTATE_STORAGE_ACCOUNT Storage account name from Step 2 (used by terraform init
                              via -backend-config)

    The script is idempotent — re-running overwrites existing values. Values that are
    already set and would not change are reported as [Exists]. Values that don't have a
    source (not in bootstrap output, not in params, not in env) are reported as
    [Skipped] with a one-line reason.

.PARAMETER GitHubOrg
    GitHub organization (or user) that owns the repo.

.PARAMETER GitHubRepo
    Repo name.

.PARAMETER SubscriptionId
    Target Azure subscription ID (becomes AZURE_SUBSCRIPTION_ID).

.PARAMETER StorageAccountName
    Storage account name from Step 2 (becomes TFSTATE_STORAGE_ACCOUNT repo variable).

.PARAMETER InputPath
    Optional. Path to the JSON file written by Bootstrap-Entra.ps1 (-OutputPath). When
    provided, AZURE_CLIENT_ID and AZURE_TENANT_ID are read from this file. Use this OR
    -ClientId/-TenantId, not both.

.PARAMETER ClientId
    Optional. OIDC SP client ID. Required if -InputPath is not provided.

.PARAMETER TenantId
    Optional. Tenant ID. Required if -InputPath is not provided. Defaults to the current
    az session's tenant if neither this nor -InputPath is given.

.PARAMETER GhPat
    SecureString. Value for the GH_PAT secret. If omitted, the script prompts.

.PARAMETER VmssAdminPassword
    SecureString. Value for the VMSS_ADMIN_PASSWORD secret. If omitted, the script
    prompts (with complexity guidance).

.PARAMETER GhSecretsPat
    Optional SecureString. Value for the GH_SECRETS_PAT secret.

.PARAMETER GhImageBuilderPat
    Optional SecureString. Value for the GH_IMAGE_BUILDER_PAT secret.

.PARAMETER GhOrganization
    Optional. Value for the GH_ORGANIZATION secret. Defaults to -GitHubOrg.

.EXAMPLE
    ./Set-GitHubSecrets.ps1 `
        -GitHubOrg 'gitspacecadet' `
        -GitHubRepo 'gh-vmss-img-runners' `
        -SubscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -StorageAccountName 'sttfstate1234' `
        -InputPath './Installation/.bootstrap-output.json'

.NOTES
    Prerequisites: gh CLI signed in with admin:repo scope on the target repo. az CLI
    signed in (only used to read tenant ID if not provided otherwise).

    VMSS_ADMIN_PASSWORD complexity: Azure requires 12+ chars, 3 of {upper, lower, digit,
    special}. The prompt validates locally before sending to GitHub.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $GitHubOrg,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $GitHubRepo,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string] $StorageAccountName,

    [Parameter()] [string] $InputPath,
    [Parameter()] [string] $ClientId,
    [Parameter()] [string] $TenantId,

    [Parameter()] [SecureString] $GhPat,
    [Parameter()] [SecureString] $VmssAdminPassword,

    [Parameter()] [SecureString] $GhSecretsPat,
    [Parameter()] [SecureString] $GhImageBuilderPat,
    [Parameter()] [string] $GhOrganization,

    [Parameter()] [string] $TfStateResourceGroupName = 'rg-terraform-state',
    [Parameter()] [string] $TfStateContainerName = 'tfstate',

    [Parameter()] [string] $RuntimeLocation = 'centralus',
    [Parameter()] [string] $RuntimeRegionSuffix = 'cus'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helpers

function Write-StepHeader {
    param([string] $Message)
    Write-Host ''
    Write-Host "===== $Message =====" -ForegroundColor Cyan
}

function Write-Action {
    param(
        [string] $Verb,
        [string] $Object,
        [ValidateSet('Set', 'Exists', 'Skipped', 'Info', 'Warn')]
        [string] $Outcome
    )
    $color = switch ($Outcome) {
        'Set'     { 'Green' }
        'Exists'  { 'Yellow' }
        'Skipped' { 'Yellow' }
        'Info'    { 'Gray' }
        'Warn'    { 'Magenta' }
    }
    Write-Host ("[{0,-7}] {1,-22} {2}" -f $Outcome, $Verb, $Object) -ForegroundColor $color
}

function ConvertFrom-SecureStringPlain {
    param([SecureString] $Secure)
    if (-not $Secure) { return $null }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Set-GhRepoSecret {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $Name,
        [string] $Value,
        [string] $Repo
    )
    if ($PSCmdlet.ShouldProcess("$Name on $Repo", 'Set GitHub repo secret')) {
        $Value | gh secret set $Name --repo $Repo --body -
        if ($LASTEXITCODE -ne 0) {
            throw "gh secret set failed for '$Name' on '$Repo'."
        }
    }
}

function Set-GhRepoVariable {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $Name,
        [string] $Value,
        [string] $Repo
    )
    if ($PSCmdlet.ShouldProcess("$Name on $Repo", 'Set GitHub repo variable')) {
        gh variable set $Name --repo $Repo --body $Value
        if ($LASTEXITCODE -ne 0) {
            throw "gh variable set failed for '$Name' on '$Repo'."
        }
    }
}

function Test-VmssPasswordComplexity {
    param([string] $Candidate)
    if (-not $Candidate -or $Candidate.Length -lt 12) { return $false }
    $classes = @(
        ($Candidate -cmatch '[A-Z]'),
        ($Candidate -cmatch '[a-z]'),
        ($Candidate -match '[0-9]'),
        ($Candidate -match '[^A-Za-z0-9]')
    )
    return (($classes | Where-Object { $_ }).Count -ge 3)
}

#endregion

#region Pre-flight + value resolution

Write-StepHeader 'Pre-flight + value resolution'

# gh auth
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Not signed in to gh CLI. Run 'gh auth login' with admin:repo scope on $GitHubOrg/$GitHubRepo."
}
Write-Action -Verb 'gh signed in' -Object 'OK' -Outcome 'Info'

$repoSlug = "$GitHubOrg/$GitHubRepo"

# Resolve ClientId + TenantId from -InputPath if provided
if ($InputPath) {
    if (-not (Test-Path $InputPath)) {
        throw "Input path '$InputPath' not found."
    }
    $bootstrap = Get-Content $InputPath -Raw | ConvertFrom-Json
    if (-not $ClientId) { $ClientId = $bootstrap.SpClientId }
    if (-not $TenantId) { $TenantId = $bootstrap.TenantId }
    Write-Action -Verb 'Loaded bootstrap' -Object $InputPath -Outcome 'Info'
}

if (-not $ClientId) {
    throw '-ClientId is required (provide via -InputPath or -ClientId).'
}
if (-not $TenantId) {
    $azAccount = az account show 2>$null | ConvertFrom-Json
    if ($azAccount) {
        $TenantId = $azAccount.tenantId
        Write-Action -Verb 'TenantId from az' -Object $TenantId -Outcome 'Info'
    } else {
        throw '-TenantId is required (provide via -InputPath, -TenantId, or run az login first).'
    }
}

# GH_PAT — prompt if not provided
if (-not $GhPat) {
    Write-Host ''
    Write-Host 'GH_PAT: a fine-grained PAT with admin permissions on the runner-target repos.' -ForegroundColor Gray
    Write-Host 'See Installation/Step3-GitHubSecrets.md for the required scopes.' -ForegroundColor Gray
    $GhPat = Read-Host 'Enter GH_PAT value' -AsSecureString
}

# VMSS_ADMIN_PASSWORD — prompt + validate complexity
if (-not $VmssAdminPassword) {
    Write-Host ''
    Write-Host 'VMSS_ADMIN_PASSWORD: 12+ chars, 3 of {upper, lower, digit, special}.' -ForegroundColor Gray
    while ($true) {
        $VmssAdminPassword = Read-Host 'Enter VMSS_ADMIN_PASSWORD' -AsSecureString
        $plain = ConvertFrom-SecureStringPlain $VmssAdminPassword
        if (Test-VmssPasswordComplexity $plain) { break }
        Write-Host 'Does not meet complexity requirements. Try again.' -ForegroundColor Red
    }
}

if (-not $GhOrganization) {
    $GhOrganization = $GitHubOrg
    Write-Action -Verb 'GhOrganization' -Object "defaulting to '$GitHubOrg'" -Outcome 'Info'
}

#endregion

#region Mandatory secrets + variable

Write-StepHeader 'Mandatory secrets + variable'

# AZURE_CLIENT_ID
Set-GhRepoSecret -Name 'AZURE_CLIENT_ID' -Value $ClientId -Repo $repoSlug
Write-Action -Verb 'AZURE_CLIENT_ID' -Object 'set from Step 1 SP' -Outcome 'Set'

# AZURE_TENANT_ID
Set-GhRepoSecret -Name 'AZURE_TENANT_ID' -Value $TenantId -Repo $repoSlug
Write-Action -Verb 'AZURE_TENANT_ID' -Object 'set' -Outcome 'Set'

# AZURE_SUBSCRIPTION_ID
Set-GhRepoSecret -Name 'AZURE_SUBSCRIPTION_ID' -Value $SubscriptionId -Repo $repoSlug
Write-Action -Verb 'AZURE_SUBSCRIPTION_ID' -Object 'set' -Outcome 'Set'

# GH_PAT
Set-GhRepoSecret -Name 'GH_PAT' -Value (ConvertFrom-SecureStringPlain $GhPat) -Repo $repoSlug
Write-Action -Verb 'GH_PAT' -Object 'set' -Outcome 'Set'

# VMSS_ADMIN_PASSWORD
Set-GhRepoSecret -Name 'VMSS_ADMIN_PASSWORD' -Value (ConvertFrom-SecureStringPlain $VmssAdminPassword) -Repo $repoSlug
Write-Action -Verb 'VMSS_ADMIN_PASSWORD' -Object 'set' -Outcome 'Set'

# TFSTATE_STORAGE_ACCOUNT (repo variable, not secret)
Set-GhRepoVariable -Name 'TFSTATE_STORAGE_ACCOUNT' -Value $StorageAccountName -Repo $repoSlug
Write-Action -Verb 'TFSTATE_STORAGE_ACCOUNT' -Object "$StorageAccountName (variable, not secret)" -Outcome 'Set'

# TFSTATE_RESOURCE_GROUP_NAME (repo variable) — replaces the hardcoded 'rg-terraform-state'
# in backend.tf so operators can pick their own naming convention without touching code
Set-GhRepoVariable -Name 'TFSTATE_RESOURCE_GROUP_NAME' -Value $TfStateResourceGroupName -Repo $repoSlug
Write-Action -Verb 'TFSTATE_RESOURCE_GROUP_NAME' -Object "$TfStateResourceGroupName (variable, not secret)" -Outcome 'Set'

# TFSTATE_CONTAINER_NAME (repo variable) — same parameterization as above for the container
Set-GhRepoVariable -Name 'TFSTATE_CONTAINER_NAME' -Value $TfStateContainerName -Repo $repoSlug
Write-Action -Verb 'TFSTATE_CONTAINER_NAME' -Object "$TfStateContainerName (variable, not secret)" -Outcome 'Set'

# RUNTIME_LOCATION (repo variable) — Azure region for the runtime infra (gallery, KV, VMSS, etc).
# Distinct from the state backend's region — that was chosen separately at Step 2 in the portal form.
# Workflows export this as TF_VAR_location, which Terraform picks up automatically.
Set-GhRepoVariable -Name 'RUNTIME_LOCATION' -Value $RuntimeLocation -Repo $repoSlug
Write-Action -Verb 'RUNTIME_LOCATION' -Object "$RuntimeLocation (variable, not secret)" -Outcome 'Set'

# RUNTIME_REGION_SUFFIX (repo variable) — short suffix used in runtime resource names
# (e.g. 'cus' in 'rg-ghrunners-dev-cus'). Should match -RuntimeLocation ('centralus' -> 'cus',
# 'eastus2' -> 'eus2'). Exported as TF_VAR_region.
Set-GhRepoVariable -Name 'RUNTIME_REGION_SUFFIX' -Value $RuntimeRegionSuffix -Repo $repoSlug
Write-Action -Verb 'RUNTIME_REGION_SUFFIX' -Object "$RuntimeRegionSuffix (variable, not secret)" -Outcome 'Set'

#endregion

#region Optional secrets

Write-StepHeader 'Optional secrets'

# GH_SECRETS_PAT
if ($GhSecretsPat) {
    Set-GhRepoSecret -Name 'GH_SECRETS_PAT' -Value (ConvertFrom-SecureStringPlain $GhSecretsPat) -Repo $repoSlug
    Write-Action -Verb 'GH_SECRETS_PAT' -Object 'set' -Outcome 'Set'
} else {
    Write-Action -Verb 'GH_SECRETS_PAT' -Object 'not provided (TF env-secret auto-sync disabled)' -Outcome 'Skipped'
}

# GH_IMAGE_BUILDER_PAT
if ($GhImageBuilderPat) {
    Set-GhRepoSecret -Name 'GH_IMAGE_BUILDER_PAT' -Value (ConvertFrom-SecureStringPlain $GhImageBuilderPat) -Repo $repoSlug
    Write-Action -Verb 'GH_IMAGE_BUILDER_PAT' -Object 'set' -Outcome 'Set'
} else {
    Write-Action -Verb 'GH_IMAGE_BUILDER_PAT' -Object 'not provided (vm-image secret auto-sync disabled)' -Outcome 'Skipped'
}

# GH_ORGANIZATION
Set-GhRepoSecret -Name 'GH_ORGANIZATION' -Value $GhOrganization -Repo $repoSlug
Write-Action -Verb 'GH_ORGANIZATION' -Object "set to '$GhOrganization'" -Outcome 'Set'

#endregion

#region Summary

Write-StepHeader 'GitHub secrets + variable seed complete'

Write-Host ''
Write-Host 'What was set on this repo:' -ForegroundColor Cyan
Write-Host ('  Repo:        {0}' -f $repoSlug) -ForegroundColor White
Write-Host ('  Mandatory:   AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, GH_PAT, VMSS_ADMIN_PASSWORD') -ForegroundColor White
Write-Host ('  Variables:   TFSTATE_STORAGE_ACCOUNT     = {0}' -f $StorageAccountName) -ForegroundColor White
Write-Host ('               TFSTATE_RESOURCE_GROUP_NAME = {0}' -f $TfStateResourceGroupName) -ForegroundColor White
Write-Host ('               TFSTATE_CONTAINER_NAME      = {0}' -f $TfStateContainerName) -ForegroundColor White
Write-Host ('               RUNTIME_LOCATION            = {0}' -f $RuntimeLocation) -ForegroundColor White
Write-Host ('               RUNTIME_REGION_SUFFIX       = {0}' -f $RuntimeRegionSuffix) -ForegroundColor White
Write-Host ('  Optional:    GH_SECRETS_PAT, GH_IMAGE_BUILDER_PAT (set if provided), GH_ORGANIZATION') -ForegroundColor White

Write-Host ''
Write-Host 'Verify in the GitHub UI:' -ForegroundColor Cyan
Write-Host ('  https://github.com/{0}/{1}/settings/secrets/actions' -f $GitHubOrg, $GitHubRepo) -ForegroundColor Gray
Write-Host ('  https://github.com/{0}/{1}/settings/variables/actions' -f $GitHubOrg, $GitHubRepo) -ForegroundColor Gray

Write-Host ''
Write-Host 'Next step: Step 4 — run Verify-Prereqs.ps1 (see Installation/Step4-Verify.md)' -ForegroundColor Cyan
