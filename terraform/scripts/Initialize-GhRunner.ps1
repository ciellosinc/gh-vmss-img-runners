param
(
    [Parameter(Mandatory = $true)]
    [string] $keyVaultName,

    [Parameter(Mandatory = $true)]
    [string] $gitHubPatSecretName,

    [Parameter(Mandatory = $true)]
    [string] $gitHubOrg,

    [Parameter(Mandatory = $false)]
    [string] $gitHubRepo = "",

    [Parameter(Mandatory = $false)]
    [string] $runnerLabels = "self-hosted,windows-latest-vmss,az-custom-image",

    # Phase 4B self-attribution. When supplied, the VM claims its own
    # VmssScalePending row before runner registration, eliminating Bug 2's
    # "highest InstanceId" sampling race in ScaleOut's queue processor.
    # Both must be set together -- null/empty disables the claim step (registration
    # proceeds normally; reconciliation in Phase 5 catches any orphaned state).
    [Parameter(Mandatory = $false)]
    [string] $storageAccountName = "",

    [Parameter(Mandatory = $false)]
    [string] $vmssName = ""
)

$logPath = "c:\vmss-runner-setup.log"
Start-Transcript -Path $logPath
$errorActionPreference = "Stop"

# Restrict ACL on transcript log so casual reads can't expose any residual sensitive data.
# Defense in depth — runner registration token is suspended out of the transcript at the
# config.cmd call site (see registration block); this ACL covers any future emissions.
try {
    $acl = Get-Acl $logPath
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators", "FullControl", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", "FullControl", "Allow")))
    Set-Acl $logPath $acl
} catch {
    Write-Host "Warning: failed to restrict log ACL: $_"
}

Write-Host "=== VMSS GitHub Runner Setup (Key Vault Integrated) ==="
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Key Vault: $keyVaultName"
Write-Host "GitHub Org: $gitHubOrg"
Write-Host "GitHub Repo: $gitHubRepo"
Write-Host "Runner Labels: $runnerLabels"
Write-Host "Storage Account (self-attribution): $storageAccountName"
Write-Host "VMSS Name (self-attribution): $vmssName"

# -----------------------------------------------------------------------------
# Self-attribution function (Arch B Phase 4B + 4C)
# -----------------------------------------------------------------------------
# RowKey conventions confirmed by ScaleOut agent:
#   VmssScalePending: PK=vmssName, RK=<utc-iso>_<runId>
#   VmssScaleTracking: PK=RK=<runId>, claim with If-Match: '*' (pending ETag already won race)
# Never throws -- registration always proceeds. Phase 5 reconciliation heals drift.
#
# Phase 4C Option A (2026-04-28): pending-row claim filters by
# VmInstanceId == $myInstanceId. ScaleOut pre-populates VmInstanceId at
# scale-out time (commit 8f0c507 in feature/phase-4c-option-a-prepop-vminstanceid;
# CI deploy run 25047247415 at 2026-04-28T10:19:30Z). Eliminates the
# cross-attribution race documented in ScaleIn docs 10/11/14.
# Retry budget [1,2,4,8,8,8]s = 31s; no fallback to first-unattributed
# (defeats Option A); on exhaustion -> [ATTR-PENDING-NOMATCH] -> DRIFT-4 heals.
# -----------------------------------------------------------------------------
function Invoke-VmssSelfAttribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StorageAccountName,
        [Parameter(Mandatory)] [string] $VmssName,
        [int] $AgeWindowMinutes = 5,
        [int] $TrackingMergeMaxAttempts = 6
    )

    $result = [pscustomobject]@{
        Attempted             = $true
        ComputeName           = $null
        InstanceId            = $null
        ClaimedRunId          = $null
        PendingClaimSuccess   = $false
        TrackingMergeSuccess  = $false
        TrackingMergeAttempts = 0
        Reason                = $null
    }

    # Capture script-start time once. Pending rows older than this minus the
    # age window are treated as orphans and ignored. 5-min default covers
    # ARM provisioning + cloud-init + script run-up; tighten if needed.
    $ageThreshold = (Get-Date).ToUniversalTime().AddMinutes(-$AgeWindowMinutes)

    try {
        $imdsHeaders = @{ Metadata = 'true' }

        # 1. IMDS: read own compute name and InstanceId. Hold both as
        # local variables so they're directly usable in MERGE bodies
        # without going through pscustomobject property access (RE-09).
        $computeName = Invoke-RestMethod -Headers $imdsHeaders `
            -Uri 'http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text' `
            -TimeoutSec 5
        $instanceId = ($computeName -split '_')[-1]
        $result.ComputeName = $computeName
        $result.InstanceId  = $instanceId
        Write-Host "[ATTR] computeName=$computeName instanceId=$instanceId computerName=$env:COMPUTERNAME ageThresholdUtc=$($ageThreshold.ToString('o'))"

        # 2. MI token for table REST
        $tokenResp = Invoke-RestMethod -Headers $imdsHeaders `
            -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/' `
            -TimeoutSec 10
        $token = $tokenResp.access_token
        if (-not $token) {
            $result.Reason = 'MI token unavailable'
            Write-Warning "[ATTR] $($result.Reason); skipping claim"
            return $result
        }

        $storageHost = "$StorageAccountName.table.core.windows.net"
        $tableHeaders = @{
            Authorization  = "Bearer $token"
            'x-ms-version' = '2019-02-02'
            Accept         = 'application/json;odata=minimalmetadata'
        }

        # 3. Phase 4C Option A: deterministic claim by VmInstanceId match.
        # ScaleOut pre-populates VmInstanceId on the pending row at scale-out time
        # (typically T_vmCreate+~5-10s via Update-AzVmss -AsJob + parallel poll).
        # CSE filters by VmInstanceId == $instanceId, eliminating the cross-attribution
        # race that motivated Phase 4C.
        #
        # Retry budget: 6 attempts with [1,2,4,8,8,8]s waits before each = 31s total.
        # Wait-before pattern (incl. attempt 1) gives ScaleOut's MERGE a 1s settling
        # head-start in the rare case CSE wins the boot race. Recency filter retained
        # as defense-in-depth: VMSS instance IDs can be reused after scale-in; a stale
        # pending row with a recycled VmInstanceId would otherwise match if Phase 5
        # reconciliation hasn't cleaned it up yet.
        #
        # No fallback to first-unattributed -- defeats Option A's purpose. On retry
        # exhaustion: [ATTR-PENDING-NOMATCH] warning, $result.Reason set, $result.PendingClaimSuccess
        # stays false. Pending row left at Status=pending; DRIFT-4 catches in ~5min.
        $retryWaits = @(1, 2, 4, 8, 8, 8)
        for ($i = 0; $i -lt $retryWaits.Count; $i++) {
            Start-Sleep -Seconds $retryWaits[$i]
            $attempt = $i + 1

            $filter = "PartitionKey eq '$VmssName' and Status eq 'pending' and VmInstanceId eq '$instanceId'"
            $listUri = "https://$storageHost/VmssScalePending()?`$filter=$filter&`$top=5"
            $rows = Invoke-RestMethod -Headers $tableHeaders -Uri $listUri -TimeoutSec 15

            $matched = @($rows.value | Where-Object {
                    if ([string]::IsNullOrWhiteSpace($_.CreatedAt)) { return $false }
                    try { $created = [DateTime]::Parse($_.CreatedAt).ToUniversalTime() }
                    catch { return $false }
                    $created -gt $ageThreshold
                })

            $row = $matched | Select-Object -First 1
            if (-not $row) {
                $totalCount = ($rows.value | Measure-Object).Count
                Write-Host "[ATTR] Attempt ${attempt}: no pending row matching VmInstanceId=$instanceId yet (total returned=$totalCount; ScaleOut MERGE may still be in flight)"
                continue
            }

            $rowKey = $row.RowKey
            $runId  = $row.WorkflowRunId
            $etag   = $row.'odata.etag'

            $claimBody = (@{
                    Status                  = 'claimed'
                    ClaimedByVmInstanceId   = $instanceId
                    ClaimedByVmInstanceName = $computeName
                    ClaimedByComputerName   = $env:COMPUTERNAME
                    ClaimedAt               = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } | ConvertTo-Json -Compress)

            $mergeHeaders = $tableHeaders.Clone()
            $mergeHeaders['If-Match'] = $etag
            $mergeHeaders['Content-Type'] = 'application/json'
            $claimUri = "https://$storageHost/VmssScalePending(PartitionKey='$VmssName',RowKey='$rowKey')"

            try {
                Invoke-RestMethod -Method Merge -Headers $mergeHeaders -Body $claimBody -Uri $claimUri -TimeoutSec 15 | Out-Null
                $result.ClaimedRunId = $runId
                $result.PendingClaimSuccess = $true
                Write-Host "[ATTR] Claimed pending row run=$runId rowKey=$rowKey on attempt $attempt by VmInstanceId match (instanceId=$instanceId)"
                break
            }
            catch {
                $code = $null
                try { $code = $_.Exception.Response.StatusCode.value__ } catch { }
                # Under Option A, each VmInstanceId maps to exactly one pending row and
                # only one CSE runs per VM. 412 ETag mismatch or other claim failure here
                # is not a transient race we can retry by picking a different row.
                Write-Warning "[ATTR] Unexpected status $code on claim of VmInstanceId=$instanceId row (run=$runId): $($_.Exception.Message)"
                $result.Reason = "Claim MERGE failed with status $code on attempt $attempt for VmInstanceId=$instanceId"
                break
            }
        }

        if (-not $result.PendingClaimSuccess -and -not $result.Reason) {
            $result.Reason = "Exhausted $($retryWaits.Count) attempts (~31s) without finding pending row matching VmInstanceId=$instanceId"
            Write-Warning "[ATTR-PENDING-NOMATCH] $($result.Reason)"
        }

        # 4. If pending-row claim succeeded, MERGE the matching tracking row.
        # Convention: PK=RK=workflowRunId. If-Match='*' is safe -- pending-row
        # ETag already won the race; only one VM ever reaches this MERGE for a
        # given runId.
        #
        # 404-retry handles the race window where ScaleOut's tracking-row write
        # lags Update-AzVmss return under burst conditions (the cmdlet can take
        # minutes to return; the tracking row is written after it returns; the
        # VM may have already booted past this MERGE by then). Backoff:
        # 2,4,8,10,10,10s = ~44s budget; comfortably exceeds typical ARM tail
        # latency. Diagnosis + fix per FromVmImageAgent/07-tracking-merge-404-retry-fix.
        if ($result.PendingClaimSuccess) {
            $trackingUri = "https://$storageHost/VmssScaleTracking(PartitionKey='$($result.ClaimedRunId)',RowKey='$($result.ClaimedRunId)')"
            $delaySeconds = 2

            Write-Host "[ATTR-TRACK] Attempting tracking MERGE: PK=RK=$($result.ClaimedRunId) table=VmssScaleTracking maxAttempts=$TrackingMergeMaxAttempts"

            for ($t = 1; $t -le $TrackingMergeMaxAttempts; $t++) {
                $result.TrackingMergeAttempts = $t
                try {
                    # RE-09: source from local $instanceId/$computeName, not $result.*.
                    # Run 24987104846 evidenced VmInstanceName missing from the MERGE body
                    # when built from $result.ComputeName -- mixed-writer field-level result
                    # on the tracking row confirmed the omission. Locals eliminate the
                    # pscustomobject access fragility (PS5.1 quirk). Pending-claim body
                    # mirrors the same pattern for parity.
                    $trackingBody = (@{
                            Status         = 'active'
                            VmInstanceId   = $instanceId
                            VmInstanceName = $computeName
                            ComputerName   = $env:COMPUTERNAME
                            AttributedAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                        } | ConvertTo-Json -Compress)

                    $trackingHeaders = $tableHeaders.Clone()
                    $trackingHeaders['If-Match'] = '*'
                    $trackingHeaders['Content-Type'] = 'application/json'

                    Invoke-RestMethod -Method Merge -Headers $trackingHeaders -Body $trackingBody -Uri $trackingUri -TimeoutSec 15 | Out-Null
                    $result.TrackingMergeSuccess = $true
                    Write-Host "[ATTR-TRACK] Tracking MERGE succeeded on attempt $t for run=$($result.ClaimedRunId)"
                    Write-Host "[ATTR] Tracking row updated for run=$($result.ClaimedRunId) (attempts=$t)"
                    break
                }
                catch {
                    $code = $null
                    try { $code = $_.Exception.Response.StatusCode.value__ } catch { }
                    $msg = $_.Exception.Message
                    Write-Host "[ATTR-TRACK] Attempt $t failed: code=$code msg=$msg"

                    if ($code -eq 404 -and $t -lt $TrackingMergeMaxAttempts) {
                        Write-Host "[ATTR-TRACK] 404 (no row yet); retrying in ${delaySeconds}s"
                        Start-Sleep -Seconds $delaySeconds
                        $delaySeconds = [Math]::Min($delaySeconds * 2, 10)
                        continue
                    }

                    # Non-404 error or final attempt: graceful degradation, log and stop.
                    Write-Warning "[ATTR-TRACK] Tracking MERGE FAILED (terminal) on attempt $t for run=$($result.ClaimedRunId): code=$code msg=$msg. Reconciliation will heal."
                    break
                }
            }

            if (-not $result.TrackingMergeSuccess) {
                Write-Warning "[ATTR] Tracking row MERGE did not succeed after $($result.TrackingMergeAttempts) attempts for run=$($result.ClaimedRunId)."
            }
        }

    }
    catch {
        $result.Reason = "Exception during attribution: $($_.Exception.Message)"
        Write-Warning "[ATTR] $($result.Reason)"
    }

    return $result
}

try {
    # ========================================
    # STEP 1: Authenticate to Azure using Managed Identity
    # ========================================
    Write-Host "Authenticating to Azure using Managed Identity..."

    # Install Az.KeyVault module if not present
    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        Write-Host "Installing Az.KeyVault module..."
        Install-Module -Name Az.KeyVault -Force -AllowClobber -Scope CurrentUser
    }

    # Connect using the VMSS Managed Identity
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Host "Successfully authenticated to Azure"

    # ========================================
    # STEP 2: Retrieve GitHub PAT from Key Vault
    # ========================================
    Write-Host "Retrieving GitHub PAT from Key Vault: $keyVaultName"

    # Use -AsPlainText on Get-AzKeyVaultSecret directly -- avoids SecureString conversion that
    # differs between PowerShell 5.1 (extension default) and PowerShell 7. Works on both.
    $gitHubPAT = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $gitHubPatSecretName -AsPlainText -ErrorAction Stop

    if ([string]::IsNullOrEmpty($gitHubPAT)) {
        Write-Error "GitHub PAT retrieved from Key Vault is empty"
        exit 1
    }
    Write-Host "Successfully retrieved GitHub PAT from Key Vault"

    # ========================================
    # STEP 3: Validate runner binaries from image
    # ========================================
    $runnerSourceDir = "C:\ProgramData\runner"
    if (!(Test-Path $runnerSourceDir)) {
        Write-Error "GitHub runner not found at $runnerSourceDir - image may not be built correctly"
        exit 1
    }

    # Check if we have the ZIP file or extracted files
    $zipFile = Get-ChildItem -Path $runnerSourceDir -Filter "actions-runner-win-x64-*.zip" | Select-Object -First 1
    $extractedFiles = Get-ChildItem -Path $runnerSourceDir -Filter "*.cmd"

    if ($zipFile -and $extractedFiles.Count -eq 0) {
        Write-Host "Found runner ZIP file: $($zipFile.Name)"
        Write-Host "Extracting runner software..."

        $tempExtractDir = Join-Path $env:TEMP "RunnerExtract"
        if (Test-Path $tempExtractDir) {
            Remove-Item -Path $tempExtractDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile.FullName, $tempExtractDir)

        Write-Host "Runner software extracted successfully"
        $runnerSourceDir = $tempExtractDir
    } elseif ($extractedFiles.Count -gt 0) {
        Write-Host "GitHub runner software already extracted in image"
    } else {
        Write-Error "No GitHub runner ZIP file or extracted files found at $runnerSourceDir"
        exit 1
    }

    # ========================================
    # STEP 4: Setup runner directory
    # ========================================
    # Runner name = <ComputerName>-<UTC yyyyMMddHHmmss>
    # Fresh-every-run timestamp gives each registration a unique audit key:
    #   * Avoids 'A runner exists with the same name' collisions when a VMSS
    #     instance ID is reused across scale events (the pre-Arch-B pattern
    #     that broke 2026-05-07 dev recovery).
    #   * Encodes registration time directly in the runner name so ScaleIn /
    #     ScaleOut reconciliation can cross-check against the tracking row's
    #     AttributedAt within a small clock-skew tolerance.
    # Reconciliation impact: matching code that previously used
    #   runner-name == ComputerName must now strip the trailing '-<14 digits>'
    #   suffix (or use exact GhRunnerName if/when added to tracking row).
    $runnerTimestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    $runnerName      = "$env:COMPUTERNAME-$runnerTimestamp"
    $runnerDir       = "C:\actions-runner\$runnerName"

    # Determine if we're registering for org or repo
    $isOrgRunner = [string]::IsNullOrEmpty($gitHubRepo)
    if ($isOrgRunner) {
        $githubApiUrl = "https://api.github.com/orgs/$gitHubOrg/actions/runners/registration-token"
        $githubRunnerUrl = "https://github.com/$gitHubOrg"
        Write-Host "Setting up runner for organization: $gitHubOrg"
    } else {
        $githubApiUrl = "https://api.github.com/repos/$gitHubOrg/$gitHubRepo/actions/runners/registration-token"
        $githubRunnerUrl = "https://github.com/$gitHubOrg/$gitHubRepo"
        Write-Host "Setting up runner for repository: $gitHubOrg/$gitHubRepo"
    }

    # ========================================
    # STEP 5: Get registration token from GitHub
    # ========================================
    Write-Host "Getting runner registration token..."
    $headers = @{
        Authorization = "token $gitHubPAT"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    try {
        $response = Invoke-RestMethod -Uri $githubApiUrl -Method Post -Headers $headers
        $runnerToken = $response.token
        Write-Host "Registration token obtained successfully"
    } catch {
        Write-Error "Failed to get registration token: $($_.Exception.Message)"
        exit 1
    }

    # ========================================
    # STEP 5.5: Self-attribution (Arch B Phase 4B + 4C)
    # ========================================
    # Claim our pending VmssScalePending row by VmInstanceId match (Phase 4C Option A)
    # + MERGE the matching tracking row. Skipped silently if the script wasn't invoked
    # with -storageAccountName/-vmssName (preserves backward compat).
    # Failures are non-fatal; Phase 5 reconciliation heals drift.
    if (-not [string]::IsNullOrWhiteSpace($storageAccountName) -and -not [string]::IsNullOrWhiteSpace($vmssName)) {
        $attr = Invoke-VmssSelfAttribution -StorageAccountName $storageAccountName -VmssName $vmssName
        Write-Host ("[ATTR] Result: PendingClaim={0} TrackingMerge={1} TrackingMergeAttempts={2} ClaimedRunId={3} Reason={4}" -f `
                $attr.PendingClaimSuccess, $attr.TrackingMergeSuccess, $attr.TrackingMergeAttempts, $attr.ClaimedRunId, $attr.Reason)
    } else {
        Write-Host "[ATTR] Self-attribution skipped (storageAccountName/vmssName not supplied)"
    }

    # ========================================
    # STEP 6: Configure and start runner
    # ========================================
    Write-Host "Setting up runner directory: $runnerDir"
    New-Item -ItemType Directory -Force -Path $runnerDir | Out-Null

    Write-Host "Copying runner files from: $runnerSourceDir"
    Copy-Item -Path "$runnerSourceDir\*" -Destination $runnerDir -Recurse -Force

    $configPath = Join-Path $runnerDir "config.cmd"
    if (-not (Test-Path $configPath)) {
        Write-Error "config.cmd not found at $configPath"
        exit 1
    }

    Set-Location $runnerDir
    Write-Host "Configuring runner: $runnerName"
    Write-Host "Runner URL: $githubRunnerUrl"
    Write-Host "Runner Labels: $runnerLabels"

    # Suspend PowerShell transcript around the registration call so the token-bearing
    # cmdline + config.cmd stdout never reach c:\vmss-runner-setup.log.
    # GitHub Actions runner has no --token-file / --token-stdin flag (verified against
    # actions/runner src/Runner.Listener/CommandSettings.cs GetToken/GetRunnerRegisterToken
    # in 2026-06-04 review), so suspending the transcript is the source-level fix.
    Stop-Transcript | Out-Null
    try {
        $configOutput = & .\config.cmd --unattended --url "$githubRunnerUrl" --token "$runnerToken" --name "$runnerName" --labels "$runnerLabels" --runAsService --windowslogonaccount "NT AUTHORITY\SYSTEM" 2>&1
        $configExit = $LASTEXITCODE
    } finally {
        Start-Transcript -Path $logPath -Append | Out-Null
    }

    # GitHub registration tokens are 29-char base32 strings starting with 'A'. Redact
    # before echoing config output so any defensive copy in stdout never reaches transcript.
    $safeOutput = ($configOutput -join "`n") -replace 'A[A-Z2-7]{28}', '[REDACTED-RUNNER-TOKEN]'
    Write-Host "Config.cmd output (token-redacted):"
    Write-Host $safeOutput
    Write-Host "Config.cmd exit code: $configExit"

    if ($configExit -eq 0) {
        Write-Host "Runner '$runnerName' configured and started successfully"
        Write-Host "VMSS instance is now ready for GitHub Actions!"
    } else {
        Write-Error "Runner configuration failed with exit code $configExit"
        exit 1
    }

} catch {
    Write-Error "Setup failed: $_"
    exit 1
} finally {
    # Clear sensitive variables from memory
    $gitHubPAT = $null
    $runnerToken = $null
    [System.GC]::Collect()

    Stop-Transcript
}

Write-Host "=== Setup Complete ==="
