<#
.SYNOPSIS
    Step 1 of the gh-vmss-img-runners installation flow — bootstrap the Entra side.

.DESCRIPTION
    Creates (or detects) the OIDC service principal that the GitHub Actions workflows in
    this repo will use to authenticate against Azure. Assigns the minimum required
    subscription-level roles, creates the GitHub deployment environments, and federates
    the SP to each environment's OIDC subject claim.

    This script is the only Entra-side action you'll take. ARM (Step 2), GitHub secrets
    (Step 3), and Terraform (Step 5) all consume what this script provisions.

    The script is idempotent — re-running it on a partially-applied state is safe.
    Existing resources are detected and skipped with informational output.

.PARAMETER GitHubOrg
    The GitHub organization (or user) that owns the repo. Example: 'gitspacecadet'.

.PARAMETER GitHubRepo
    The repo name. Example: 'gh-vmss-img-runners'.

.PARAMETER SubscriptionId
    The Azure subscription ID where the runner infrastructure will be deployed.

.PARAMETER SpName
    Display name for the OIDC service principal. Defaults to
    "GitHub-OIDC-GHRunners-<GitHubOrg>". The default keeps the SP namespaced per org so
    multiple installs in the same tenant don't collide.

.PARAMETER Environments
    GitHub environments to create + federate. Defaults to the 6 the terraform-deploy
    and terraform-ci workflows expect: dev, test, prod, dev-plan, test-plan, prod-plan.

.PARAMETER OutputPath
    Optional. Path to write the structured result (SP clientId/objectId/tenantId) as JSON
    so Step 2 and Step 3 can consume it. If omitted, the structured object is only
    written to the pipeline.

.EXAMPLE
    ./Bootstrap-Entra.ps1 `
        -GitHubOrg 'gitspacecadet' `
        -GitHubRepo 'gh-vmss-img-runners' `
        -SubscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -OutputPath './Installation/.bootstrap-output.json'

.NOTES
    Prerequisites: az CLI (signed in), gh CLI (signed in) with admin rights on the repo,
    PowerShell 7+. Run from any directory; paths are not assumed.

    Why subscription-level Contributor + User Access Administrator:
    - Contributor: Terraform creates RGs, VMSS, function apps, KV, storage accounts
    - User Access Administrator: Terraform assigns RBAC roles to the managed identities
      it creates (via `azurerm_role_assignment` resources)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $GitHubOrg,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $GitHubRepo,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $SubscriptionId,

    [Parameter()]
    [string] $SpName = "GitHub-OIDC-GHRunners-$GitHubOrg",

    [Parameter()]
    [string[]] $Environments = @('dev', 'test', 'prod', 'dev-plan', 'test-plan', 'prod-plan'),

    [Parameter()]
    [string] $OutputPath
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
        [ValidateSet('Created', 'Exists', 'Updated', 'Skipped', 'Info')]
        [string] $Outcome
    )
    $color = switch ($Outcome) {
        'Created' { 'Green' }
        'Updated' { 'Green' }
        'Exists'  { 'Yellow' }
        'Skipped' { 'Yellow' }
        'Info'    { 'Gray' }
    }
    Write-Host ("[{0,-7}] {1,-12} {2}" -f $Outcome, $Verb, $Object) -ForegroundColor $color
}

function Test-CommandPresence {
    param([string] $Name)
    [bool] (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-AzCall {
    <#
    .SYNOPSIS
        Wraps an az CLI invocation with $LASTEXITCODE checking + separate stdout/stderr capture.
    .DESCRIPTION
        Without this, az writes errors to stderr but $LASTEXITCODE is the only reliable success
        signal. Pipe operators like '| Out-Null' suppress stdout but NOT stderr, so failures look
        like "scary message printed, then we continued anyway".

        This helper redirects stderr to a temp file so we can:
          - Return CLEAN stdout from the scriptblock (no stderr pollution into our $existingX checks)
          - On failure (LASTEXITCODE != 0), read the stderr content and surface it in the thrown error
          - Detect the well-known Status_InteractionRequired pattern and append a remediation hint
    .EXAMPLE
        Invoke-AzCall { az group list --query '[0].id' -o tsv }
    #>
    param(
        [Parameter(Mandatory)] [scriptblock] $Script,
        [Parameter()] [string] $ContextHint
    )
    $errorFile = [System.IO.Path]::GetTempFileName()
    try {
        $output = & $Script 2>$errorFile
        if ($LASTEXITCODE -ne 0) {
            $stderr = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
            $message = "az command failed (exit $LASTEXITCODE)"
            if ($ContextHint) { $message += " during $ContextHint" }
            if ($stderr) { $message += ":`n$stderr" }
            if ($stderr -and ($stderr -match 'Status_InteractionRequired|InteractionRequired')) {
                $message += "`n`nHINT: your cached az token lacks an ARM-scoped grant. Run:`n  az login --scope https://management.core.windows.net//.default`nthen re-run this script (idempotent — already-created resources are skipped)."
            }
            throw $message
        }
        return $output
    } finally {
        Remove-Item $errorFile -ErrorAction SilentlyContinue
    }
}

#endregion

#region Pre-flight

Write-StepHeader 'Pre-flight checks'

foreach ($cmd in 'az', 'gh') {
    if (-not (Test-CommandPresence $cmd)) {
        throw "Required CLI '$cmd' not found in PATH. Install it before running this script."
    }
    Write-Action -Verb 'CLI found' -Object $cmd -Outcome 'Info'
}

# az auth
$azAccount = az account show 2>$null | ConvertFrom-Json
if (-not $azAccount) {
    throw "Not signed in to az. Run 'az login' first."
}
if ($azAccount.id -ne $SubscriptionId) {
    Write-Action -Verb 'Setting sub' -Object $SubscriptionId -Outcome 'Info'
    az account set --subscription $SubscriptionId | Out-Null
    $azAccount = az account show | ConvertFrom-Json
}
Write-Action -Verb 'az signed in' -Object "$($azAccount.user.name) -> $($azAccount.name)" -Outcome 'Info'
$tenantId = $azAccount.tenantId

# ARM token probe — catches Status_InteractionRequired BEFORE we start writing.
# A fresh `az login` sometimes leaves the cached token without the management.core scope
# granted; later role assignment writes fail with a confusing 'Status_InteractionRequired'
# error. Probing a benign ARM read upfront converts that into a clean abort with a clear
# remediation message (see Invoke-AzCall helper).
try {
    Invoke-AzCall -ContextHint 'ARM probe' -Script { az group list --query '[0].id' -o tsv } | Out-Null
    Write-Action -Verb 'ARM reachable' -Object 'OK' -Outcome 'Info'
} catch {
    throw $_
}

# gh auth
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Not signed in to gh CLI. Run 'gh auth login' with admin rights on $GitHubOrg/$GitHubRepo."
}
Write-Action -Verb 'gh signed in' -Object 'OK' -Outcome 'Info'

# Repo reachability
$repoCheck = gh api "repos/$GitHubOrg/$GitHubRepo" --jq '.full_name' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $repoCheck) {
    throw "Cannot reach repo $GitHubOrg/$GitHubRepo. Check the org/repo name and that your gh PAT has access."
}
Write-Action -Verb 'Repo reachable' -Object $repoCheck -Outcome 'Info'

#endregion

#region Step 1 — Service Principal

Write-StepHeader "Service Principal: $SpName"

$existingSp = az ad sp list --filter "displayName eq '$SpName'" --query '[0]' -o json 2>$null | ConvertFrom-Json
if ($existingSp) {
    Write-Action -Verb 'SP' -Object $SpName -Outcome 'Exists'
    $spClientId = $existingSp.appId
    $spObjectId = $existingSp.id
    $appObjectId = (az ad app show --id $spClientId --query 'id' -o tsv)
} else {
    if ($PSCmdlet.ShouldProcess($SpName, 'Create OIDC service principal')) {
        Write-Action -Verb 'SP' -Object $SpName -Outcome 'Created'
        $appJson = az ad app create --display-name $SpName --query '{appId:appId,id:id}' -o json | ConvertFrom-Json
        $spClientId = $appJson.appId
        $appObjectId = $appJson.id

        # Materialize the SP so role assignments and FICs can reference it
        $spJson = az ad sp create --id $spClientId --query 'id' -o json | ConvertFrom-Json
        $spObjectId = $spJson
    } else {
        throw 'SP creation declined; aborting before partial state.'
    }
}

#endregion

#region Step 2 — Subscription role assignments

Write-StepHeader "Subscription roles for $SpName"

$subScope = "/subscriptions/$SubscriptionId"
$requiredRoles = @('Contributor', 'User Access Administrator')

foreach ($role in $requiredRoles) {
    $existingAssignment = Invoke-AzCall -ContextHint "role assignment list ($role)" -Script {
        az role assignment list `
            --assignee-object-id $spObjectId `
            --assignee-principal-type ServicePrincipal `
            --role $role `
            --scope $subScope `
            --query '[0].id' -o tsv
    }

    if ($existingAssignment) {
        Write-Action -Verb 'Role' -Object $role -Outcome 'Exists'
    } else {
        if ($PSCmdlet.ShouldProcess("$role on $subScope", "Assign role to SP $SpName")) {
            Invoke-AzCall -ContextHint "role assignment create ($role)" -Script {
                az role assignment create `
                    --assignee-object-id $spObjectId `
                    --assignee-principal-type ServicePrincipal `
                    --role $role `
                    --scope $subScope
            } | Out-Null
            Write-Action -Verb 'Role' -Object $role -Outcome 'Created'
        }
    }
}

#endregion

#region Step 3 — GitHub environments

Write-StepHeader 'GitHub environments'

foreach ($env in $Environments) {
    $envCheck = gh api "repos/$GitHubOrg/$GitHubRepo/environments/$env" --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $envCheck) {
        Write-Action -Verb 'Env' -Object $env -Outcome 'Exists'
    } else {
        if ($PSCmdlet.ShouldProcess($env, "Create GitHub environment in $GitHubOrg/$GitHubRepo")) {
            gh api -X PUT "repos/$GitHubOrg/$GitHubRepo/environments/$env" --silent 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Action -Verb 'Env' -Object $env -Outcome 'Created'
            } else {
                throw "Failed to create GitHub environment '$env'. Check your gh PAT has admin:repo or repo write scope."
            }
        }
    }
}

#endregion

#region Step 4 — Federated Identity Credentials

Write-StepHeader 'Federated Identity Credentials'

$existingFics = az ad app federated-credential list --id $appObjectId -o json | ConvertFrom-Json

foreach ($env in $Environments) {
    $subject = "repo:$GitHubOrg/$GitHubRepo`:environment:$env"
    $ficName = "gh-$env"
    $match = $existingFics | Where-Object { $_.subject -eq $subject }

    if ($match) {
        Write-Action -Verb 'FIC' -Object "$ficName ($subject)" -Outcome 'Exists'
    } else {
        if ($PSCmdlet.ShouldProcess($subject, 'Create federated identity credential')) {
            # PowerShell + az CLI + inline JSON string for --parameters is broken: PS strips
            # the double-quotes when passing the string as a command-line arg, az then sees
            # bare-key JSON ({audiences:[...]}) and fails with "Failed to parse string as JSON".
            # The robust fix is to write the JSON to a temp file and use --parameters @<file>.
            # See https://github.com/Azure/azure-cli/blob/dev/doc/quoting-issues-with-powershell.md
            $ficSpec = @{
                name      = $ficName
                issuer    = 'https://token.actions.githubusercontent.com'
                subject   = $subject
                audiences = @('api://AzureADTokenExchange')
                description = "OIDC for $GitHubOrg/$GitHubRepo on env $env"
            }
            $tempFile = New-TemporaryFile
            try {
                $ficSpec | ConvertTo-Json -Compress | Out-File -FilePath $tempFile.FullName -Encoding utf8 -NoNewline
                Invoke-AzCall -ContextHint "federated-credential create ($ficName)" -Script {
                    az ad app federated-credential create --id $appObjectId --parameters "@$($tempFile.FullName)"
                } | Out-Null
                Write-Action -Verb 'FIC' -Object "$ficName ($subject)" -Outcome 'Created'
            } finally {
                Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
            }
        }
    }
}

#endregion

#region Output

Write-StepHeader 'Bootstrap complete'

$result = [PSCustomObject] @{
    SpName         = $SpName
    SpClientId     = $spClientId
    SpObjectId     = $spObjectId
    AppObjectId    = $appObjectId
    TenantId       = $tenantId
    SubscriptionId = $SubscriptionId
    GitHubOrg      = $GitHubOrg
    GitHubRepo     = $GitHubRepo
    Environments   = $Environments
}

Write-Host ''
Write-Host 'Capture these values for the next steps:' -ForegroundColor Cyan
Write-Host ('  SP Client ID    (AZURE_CLIENT_ID)       : {0}' -f $spClientId) -ForegroundColor White
Write-Host ('  SP Object ID    (for ARM template input): {0}' -f $spObjectId) -ForegroundColor White
Write-Host ('  Tenant ID       (AZURE_TENANT_ID)       : {0}' -f $tenantId) -ForegroundColor White
Write-Host ('  Subscription ID (AZURE_SUBSCRIPTION_ID) : {0}' -f $SubscriptionId) -ForegroundColor White

if ($OutputPath) {
    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Host ''
    Write-Host "Structured output written to: $OutputPath" -ForegroundColor Gray
    Write-Host '(Recommend adding this path to .gitignore — it contains object IDs but no secrets.)' -ForegroundColor Gray
}

Write-Host ''
Write-Host 'Next step: Step 2 — click the Deploy-to-Azure button (see Installation/Step2-AzurePrereqs.md)' -ForegroundColor Cyan

# Emit structured object so the caller can pipe it
$result
