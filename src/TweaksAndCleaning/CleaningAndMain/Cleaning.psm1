# Cleaning.psm1
# Quinn Optimiser Toolkit – Cleaning module
# Contains safe system cleaning operations (temp files, caches, logs, etc.)

# ------------------------------
# Import core logging
# ------------------------------
Import-Module "$PSScriptRoot\..\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force

function New-QOTTaskResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("Success","Skipped","Failed")][string]$Status,
        [string]$Reason,
        [string]$Error
    )

    [pscustomobject]@{
        Name   = $Name
        Status = $Status
        Reason = $Reason
        Error  = $Error
    }
}

function New-QOTOperationResult {
    param(
        [Parameter(Mandatory)][ValidateSet("Success","Skipped","Failed")][string]$Status,
        [string]$Reason,
        [string]$Error
    )

    [pscustomobject]@{
        Status = $Status
        Reason = $Reason
        Error  = $Error
    }
}

function Resolve-QOTTaskResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object[]]$Operations
    )

    $failed = @($Operations | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($Operations | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($Operations | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
}

function Write-QOTTaskOutcome {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][object]$Result
    )

    $status = "SKIPPED"
    try {
        switch ([string]$Result.Status) {
            "Success" { $status = "SUCCESS" }
            "Failed" { $status = "FAILED" }
            default { $status = "SKIPPED" }
        }
    } catch { }

    $reason = $null
    try { $reason = [string]$Result.Reason } catch { $reason = $null }
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Write-QLog ("Task result: {0} => {1} ({2})" -f $TaskName, $status, $reason)
    } else {
        Write-QLog ("Task result: {0} => {1}" -f $TaskName, $status)
    }
}

function Test-QOTAdminRequiredFailure {
    param([Parameter(Mandatory)][object]$ErrorRecord)

    if (-not $ErrorRecord -or -not $ErrorRecord.Exception) { return $false }
    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match "Access to the path .* is denied" -or $message -match "Access is denied") {
        return $true
    }
    return $false
}

function Invoke-QOTClearFolderContents {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
            return New-QOTOperationResult -Status "Failed" -Reason "requires admin"
        }
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }

    if ($items.Count -eq 0) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
    }

    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        }
        catch {
            if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
                return New-QOTOperationResult -Status "Failed" -Reason "requires admin"
            }
            return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
        }
    }

    Write-QLog ("Cleaning: {0} (done)" -f $Label)
    return New-QOTOperationResult -Status "Success"
}

function Invoke-QCleanPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label
    )

    if ($Label -and $Label -isnot [string]) {
        $Label = [string]$Label
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Label) {
            Write-QLog ("Cleaning: {0} (skip, not found)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Path not found: {0}" -f $Path)
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        $removedAny = $false
        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $removedAny = $true
            } catch { }
        }
        if ($Label) {
            Write-QLog ("Cleaning: {0} (done)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Cleared {0}" -f $Path)
        }
        if ($removedAny) {
            return New-QOTOperationResult -Status "Success"
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Already done"
    }
    catch {
        if ($Label) {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Label, $_.Exception.Message) "ERROR"
        } else {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Path, $_.Exception.Message) "ERROR"
        }
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}

function Invoke-QCleanPathFiles {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Filter,
        [string]$Label
    )

    if ($Label -and $Label -isnot [string]) {
        $Label = [string]$Label
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Label) {
            Write-QLog ("Cleaning: {0} (skip, not found)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Path not found: {0}" -f $Path)
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Filter $Filter -Force -ErrorAction SilentlyContinue
        $removedAny = $false
        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $removedAny = $true
            } catch { }
        }
        if ($Label) {
            Write-QLog ("Cleaning: {0} (done)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Cleared {0}\\{1}" -f $Path, $Filter)
        }
        if ($removedAny) {
            return New-QOTOperationResult -Status "Success"
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }
    catch {
        if ($Label) {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Label, $_.Exception.Message) "ERROR"
        } else {
            Write-QLog ("Cleaning: {0}\\{1} failed: {2}" -f $Path, $Filter, $_.Exception.Message) "ERROR"
        }
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}


# ------------------------------
# Public: Clean Windows Update cache
# (placeholder for now, real logic added later)
# ------------------------------
function Invoke-QCleanWindowsUpdateCache {
    Write-QLog "Cleaning: Windows Update cache"
    $serviceName = "wuauserv"
    try { Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue } catch { }
    $op = Invoke-QCleanPath -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label "Windows Update cache"
    try { Start-Service -Name $serviceName -ErrorAction SilentlyContinue } catch { }
    return Resolve-QOTTaskResult -Name "Windows Update cache" -Operations @($op)
}

# ------------------------------
# Public: Clean Delivery Optimisation cache
# ------------------------------
function Invoke-QCleanDOCache {
    Write-QLog "Cleaning: Delivery Optimisation cache"
    $op = Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache" -Label "Delivery Optimisation cache"
    return Resolve-QOTTaskResult -Name "Delivery Optimisation cache" -Operations @($op)
}

# ------------------------------
# Public: Clear temp folders
# ------------------------------
function Invoke-QCleanTemp {
    Write-QLog "Cleaning: Temp folders"
    $ops = @(
        Invoke-QCleanPath -Path $env:TEMP -Label "User temp files"
        Invoke-QCleanPath -Path $env:TMP -Label "User tmp files"
        Invoke-QCleanPath -Path "$env:SystemRoot\Temp" -Label "Windows temp files"
    )
    return Resolve-QOTTaskResult -Name "Temp folders" -Operations $ops
}

# ------------------------------
# Public: Empty Recycle Bin
# ------------------------------
function Invoke-QCleanRecycleBin {
    Write-QLog "Cleaning: Recycle Bin"
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        Write-QLog "Cleaning: Recycle Bin (done)"
        return New-QOTTaskResult -Name "Recycle Bin" -Status "Success"
    }
    catch {
        Write-QLog ("Cleaning: Recycle Bin failed: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTTaskResult -Name "Recycle Bin" -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}

# ------------------------------
# Public: Thumbnail cache
# ------------------------------
function Invoke-QCleanThumbnailCache {
    Write-QLog "Cleaning: Thumbnail cache"
    $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    $ops = @(
        Invoke-QCleanPathFiles -Path $thumbPath -Filter "thumbcache*.db" -Label "Thumbnail cache"
        Invoke-QCleanPathFiles -Path $thumbPath -Filter "iconcache*.db" -Label "Icon cache"
    )
    return Resolve-QOTTaskResult -Name "Thumbnail cache" -Operations $ops
}

# ------------------------------
# Public: Error logs / crash dumps
# ------------------------------
function Invoke-QCleanErrorLogs {
    Write-QLog "Cleaning: Error logs and crash dumps"
    $ops = @(
        Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Label "Windows Error Reporting archives"
        Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Label "Windows Error Reporting queue"
        Invoke-QCleanPath -Path "$env:LOCALAPPDATA\CrashDumps" -Label "User crash dumps"
    )
    return Resolve-QOTTaskResult -Name "Error logs" -Operations $ops
}

# ------------------------------
# Public: Setup / upgrade leftovers
# ------------------------------
function Invoke-QCleanSetupLeftovers {
    Write-QLog "Cleaning: Setup/upgrade leftovers"
    $ops = @(
        Invoke-QCleanPath -Path "$env:SystemDrive\Windows.old" -Label "Windows.old"
        Invoke-QCleanPath -Path "$env:SystemDrive\`$WINDOWS.~BT" -Label "Setup cache (`$WINDOWS.~BT)"
        Invoke-QCleanPath -Path "$env:SystemDrive\`$WINDOWS.~WS" -Label "Setup cache (`$WINDOWS.~WS)"
        Invoke-QCleanPath -Path "$env:SystemDrive\ESD" -Label "Windows ESD"
        Invoke-QCleanPath -Path "$env:SystemRoot\Panther" -Label "Setup log files"
    )
    return Resolve-QOTTaskResult -Name "Setup leftovers" -Operations $ops
}

# ------------------------------
# Public: Microsoft Store cache
# ------------------------------
function Invoke-QCleanStoreCache {
    Write-QLog "Cleaning: Microsoft Store cache"

    $storeCacheBase = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsStore_8wekyb3d8bbwe"
    $ops = @(
        Invoke-QCleanPath -Path (Join-Path $storeCacheBase "LocalCache") -Label "Store LocalCache"
        Invoke-QCleanPath -Path (Join-Path $storeCacheBase "TempState") -Label "Store TempState"
        Invoke-QCleanPath -Path (Join-Path $storeCacheBase "AC\INetCache") -Label "Store INetCache"
    )

    $result = Resolve-QOTTaskResult -Name "Store cache" -Operations $ops
    if ($result.Status -eq "Skipped") {
        Write-QLog "Cleaning: Microsoft Store cache (skip, no cache folders found)"
    } elseif ($result.Status -eq "Success") {
        Write-QLog "Cleaning: Microsoft Store cache (done)"
    }
    return $result  
}

# ------------------------------
# Public: Edge cache cleanup (light)
# ------------------------------
function Invoke-QCleanEdgeCache {
    Write-QLog "Cleaning: Edge cache cleanup"
    $edgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    $ops = @(
        Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\Cache") -Label "Edge Cache"
        Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\Code Cache") -Label "Edge Code Cache"
        Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\GPUCache") -Label "Edge GPU Cache"
    )
    return Resolve-QOTTaskResult -Name "Edge cache" -Operations $ops
}

# ------------------------------
# Public: Chrome/Chromium cache cleanup (light)
# ------------------------------
function Invoke-QCleanChromeCache {
    Write-QLog "Cleaning: Chrome/Chromium cache cleanup"
    $chromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    $ops = @(
        Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\Cache") -Label "Chrome Cache"
        Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\Code Cache") -Label "Chrome Code Cache"
        Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\GPUCache") -Label "Chrome GPU Cache"
    )
    return Resolve-QOTTaskResult -Name "Chrome cache" -Operations $ops
}

function Invoke-QCleanDirectXShaderCache {
    $taskName = "Clear DirectX shader cache"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $result = Resolve-QOTTaskResult -Name $taskName -Operations @(
        Invoke-QOTClearFolderContents -Path "$env:LOCALAPPDATA\D3DSCache" -Label "DirectX shader cache"
    )
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanWERQueue {
    $taskName = "Clear Windows Error Reporting queue"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $ops = @(
        Invoke-QOTClearFolderContents -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Label "WER ReportQueue"
        Invoke-QOTClearFolderContents -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Label "WER ReportArchive"
    )
    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanClipboardHistory {
    $taskName = "Clear clipboard history"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $ops = @()
    try {
        if (Get-Command -Name "Set-Clipboard" -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value "" -ErrorAction Stop
            $ops += New-QOTOperationResult -Status "Success"
        } else {
            $ops += New-QOTOperationResult -Status "Skipped" -Reason "Set-Clipboard unavailable"
        }
    }
    catch {
        $ops += New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }

    $ops += Invoke-QOTClearFolderContents -Path "$env:LOCALAPPDATA\Microsoft\Clipboard" -Label "Clipboard history"

    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanExplorerRecentItems {
    $taskName = "Clear Explorer Recent items and Jump Lists"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
    $ops = @(
        Invoke-QOTClearFolderContents -Path $recentPath -Label "Explorer recent items"
        Invoke-QOTClearFolderContents -Path (Join-Path $recentPath "AutomaticDestinations") -Label "Jump Lists (automatic)"
        Invoke-QOTClearFolderContents -Path (Join-Path $recentPath "CustomDestinations") -Label "Jump Lists (custom)"
    )

    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanWindowsSearchHistory {
    $taskName = "Clear Windows Search history"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery"
    if (-not (Test-Path -LiteralPath $path)) {
        $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Search history key not found"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }

    try {
        $props = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $propNames = @($props.PSObject.Properties | Where-Object { $_.Name -match '^\d+$|^MRUListEx$' } | ForEach-Object { $_.Name })
        if ($propNames.Count -eq 0) {
            $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "No user search history entries found"
            Write-QOTTaskOutcome -TaskName $taskName -Result $result
            return $result
        }

        foreach ($name in $propNames) {
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop
        }

        $result = New-QOTTaskResult -Name $taskName -Status "Success"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }
    catch {
        $reason = "Cleanup failed"
        if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
            $reason = "requires admin"
        }
        $result = New-QOTTaskResult -Name $taskName -Status "Failed" -Reason $reason -Error $_.Exception.Message
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }
}


# ------------------------------
# Export functions
# ------------------------------
Export-ModuleMember -Function `
    Invoke-QCleanWindowsUpdateCache, `
    Invoke-QCleanDOCache, `
    Invoke-QCleanTemp, `
    Invoke-QCleanRecycleBin, `
    Invoke-QCleanThumbnailCache, `
    Invoke-QCleanErrorLogs, `
    Invoke-QCleanSetupLeftovers, `
    Invoke-QCleanStoreCache, `
    Invoke-QCleanEdgeCache, `
    Invoke-QCleanChromeCache, `
    Invoke-QCleanDirectXShaderCache, `
    Invoke-QCleanWERQueue, `
    Invoke-QCleanClipboardHistory, `
    Invoke-QCleanExplorerRecentItems, `
    Invoke-QCleanWindowsSearchHistory
