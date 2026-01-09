# Cleaning.psm1
# Quinn Optimiser Toolkit – Cleaning module
# Contains safe system cleaning operations (temp files, caches, logs, etc.)

# ------------------------------
# Import core logging
# ------------------------------
Import-Module "$PSScriptRoot\..\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force


function Invoke-QCleanPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Label) {
            Write-QLog ("Cleaning: {0} (skip, not found)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Path not found: {0}" -f $Path)
        }
        return
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            } catch { }
        }
        if ($Label) {
            Write-QLog ("Cleaning: {0} (done)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Cleared {0}" -f $Path)
        }
    }
    catch {
        if ($Label) {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Label, $_.Exception.Message) "ERROR"
        } else {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Path, $_.Exception.Message) "ERROR"
        }
    }
}

function Invoke-QCleanPathFiles {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Filter,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Label) {
            Write-QLog ("Cleaning: {0} (skip, not found)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Path not found: {0}" -f $Path)
        }
        return
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Filter $Filter -Force -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
            } catch { }
        }
        if ($Label) {
            Write-QLog ("Cleaning: {0} (done)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Cleared {0}\\{1}" -f $Path, $Filter)
        }
    }
    catch {
        if ($Label) {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Label, $_.Exception.Message) "ERROR"
        } else {
            Write-QLog ("Cleaning: {0}\\{1} failed: {2}" -f $Path, $Filter, $_.Exception.Message) "ERROR"
        }
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
    Invoke-QCleanPath -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label "Windows Update cache"
    try { Start-Service -Name $serviceName -ErrorAction SilentlyContinue } catch { }
}

# ------------------------------
# Public: Clean Delivery Optimisation cache
# ------------------------------
function Invoke-QCleanDOCache {
    Write-QLog "Cleaning: Delivery Optimisation cache"
    Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache" -Label "Delivery Optimisation cache"
}

# ------------------------------
# Public: Clear temp folders
# ------------------------------
function Invoke-QCleanTemp {
    Write-QLog "Cleaning: Temp folders"
    Invoke-QCleanPath -Path $env:TEMP -Label "User temp files"
    Invoke-QCleanPath -Path $env:TMP -Label "User tmp files"
    Invoke-QCleanPath -Path "$env:SystemRoot\Temp" -Label "Windows temp files"
}

# ------------------------------
# Public: Empty Recycle Bin
# ------------------------------
function Invoke-QCleanRecycleBin {
    Write-QLog "Cleaning: Recycle Bin"
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        Write-QLog "Cleaning: Recycle Bin (done)"
    }
    catch {
        Write-QLog ("Cleaning: Recycle Bin failed: {0}" -f $_.Exception.Message) "ERROR"
    }
}

# ------------------------------
# Public: Thumbnail cache
# ------------------------------
function Invoke-QCleanThumbnailCache {
    Write-QLog "Cleaning: Thumbnail cache"
    $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    Invoke-QCleanPathFiles -Path $thumbPath -Filter "thumbcache*.db" -Label "Thumbnail cache"
    Invoke-QCleanPathFiles -Path $thumbPath -Filter "iconcache*.db" -Label "Icon cache"
}

# ------------------------------
# Public: Error logs / crash dumps
# ------------------------------
function Invoke-QCleanErrorLogs {
    Write-QLog "Cleaning: Error logs and crash dumps"
    Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Label "Windows Error Reporting archives"
    Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Label "Windows Error Reporting queue"
    Invoke-QCleanPath -Path "$env:LOCALAPPDATA\CrashDumps" -Label "User crash dumps"
}

# ------------------------------
# Public: Setup / upgrade leftovers
# ------------------------------
function Invoke-QCleanSetupLeftovers {
    Write-QLog "Cleaning: Setup/upgrade leftovers"
    Invoke-QCleanPath -Path "$env:SystemDrive\Windows.old" -Label "Windows.old"
    Invoke-QCleanPath -Path "$env:SystemDrive\`$WINDOWS.~BT" -Label "Setup cache (`$WINDOWS.~BT)"
    Invoke-QCleanPath -Path "$env:SystemDrive\`$WINDOWS.~WS" -Label "Setup cache (`$WINDOWS.~WS)"
    Invoke-QCleanPath -Path "$env:SystemDrive\ESD" -Label "Windows ESD"
    Invoke-QCleanPath -Path "$env:SystemRoot\Panther" -Label "Setup log files"
}

# ------------------------------
# Public: Microsoft Store cache
# ------------------------------
function Invoke-QCleanStoreCache {
    Write-QLog "Cleaning: Microsoft Store cache"
    try {
        Start-Process -FilePath "wsreset.exe" -Wait -WindowStyle Hidden
        Write-QLog "Cleaning: Microsoft Store cache (done)"
    }
    catch {
        Write-QLog ("Cleaning: Microsoft Store cache failed: {0}" -f $_.Exception.Message) "ERROR"
    }
}

# ------------------------------
# Public: Edge cache cleanup (light)
# ------------------------------
function Invoke-QCleanEdgeCache {
    Write-QLog "Cleaning: Edge cache cleanup"
    $edgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\Cache") -Label "Edge Cache"
    Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\Code Cache") -Label "Edge Code Cache"
    Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\GPUCache") -Label "Edge GPU Cache"
}

# ------------------------------
# Public: Chrome/Chromium cache cleanup (light)
# ------------------------------
function Invoke-QCleanChromeCache {
    Write-QLog "Cleaning: Chrome/Chromium cache cleanup"
    $chromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\Cache") -Label "Chrome Cache"
    Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\Code Cache") -Label "Chrome Code Cache"
    Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\GPUCache") -Label "Chrome GPU Cache"
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
    Invoke-QCleanChromeCache
