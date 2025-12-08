# InstalledApps.psm1
# Scanning and risk logic for installed applications

param()

# Make sure logging is available if module is loaded directly
try {
    if (-not (Get-Command Write-QLog -ErrorAction SilentlyContinue)) {
        Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction SilentlyContinue
    }
} catch { }

# Whitelist patterns for protected apps
$Global:QOT_AppWhitelistPatterns = @(
    "Genesys",
    "GenesysCloud",
    "FortiClient",
    "Fortinet",
    "ScreenConnect",
    "ConnectWise",
    "Sophos",
    "Microsoft 365",
    "Microsoft Office",
    "Teams",
    "Word",
    "PowerPoint",
    "Outlook"
)

function Get-QOTAppWhitelist {
    <#
        .SYNOPSIS
            Returns the whitelist patterns used to protect critical apps.
    #>
    return $Global:QOT_AppWhitelistPatterns
}

function Get-QOTInstalledApps {
    <#
        .SYNOPSIS
            Scans common registry locations for installed applications and
            returns normalised objects for the UI / engine.
    #>

    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $_.DisplayName) { return }

            $isSystem = $false

            if ($_.SystemComponent -eq 1) { $isSystem = $true }
            if ($_.ReleaseType -eq "Security Update" -or $_.ParentKeyName) { $isSystem = $true }
            if ($_.DisplayName -match "Driver|Runtime|Redistributable|Update|Hotfix") { $isSystem = $true }
            if ($_.Publisher -match "Microsoft|Intel|NVIDIA|Realtek|AMD") { $isSystem = $true }

            $sizeMB = $null
            if ($_.EstimatedSize) {
                $sizeMB = [math]::Round($_.EstimatedSize / 1024, 1)
            }

            $installDate = $null
            if ($_.InstallDate -and $_.InstallDate -match "^\d{8}$") {
                try {
                    $parsed = $null
                    if ([datetime]::TryParseExact(
                            $_.InstallDate,
                            "yyyyMMdd",
                            $null,
                            [System.Globalization.DateTimeStyles]::None,
                            [ref]$parsed
                        )) {
                        $installDate = $parsed
                    }
                    else {
                        try { Write-QLog "Invalid InstallDate '$($_.InstallDate)' for $($_.DisplayName)" "WARN" } catch { }
                    }
                }
                catch {
                    try {
                        Write-QLog "Error parsing InstallDate '$($_.InstallDate)' for $($_.DisplayName): $($_.Exception.Message)" "WARN"
                    } catch { }
                }
            }

            $isWhitelisted = $false
            foreach ($pattern in $Global:QOT_AppWhitelistPatterns) {
                if ($_.DisplayName -like "*$pattern*") {
                    $isWhitelisted = $true
                    break
                }
            }

            [PSCustomObject]@{
                Name            = $_.DisplayName
                Publisher       = $_.Publisher
                SizeMB          = $sizeMB
                InstallDate     = $installDate
                IsSystem        = $isSystem
                IsWhitelisted   = $isWhitelisted
                UninstallString = $_.UninstallString
                LastUsed        = $installDate   # placeholder for future usage tracking
            }
        }
    }

    $apps | Sort-Object Name -Unique
}

function Get-QOTAppRisk {
    <#
        .SYNOPSIS
            Returns a simple risk label for an app: Protected / Red / Amber / Green.
    #>
    param(
        [Parameter(Mandatory)]
        $App
    )

    if ($App.IsWhitelisted) { return "Protected" }
    if ($App.IsSystem -or -not $App.UninstallString) { return "Red" }

    $days = $null
    if ($App.InstallDate) {
        $days = (New-TimeSpan -Start $App.InstallDate -End (Get-Date)).Days
    }

    if (($App.SizeMB -ge 500) -or ($days -ge 365)) { return "Amber" }

    return "Green"
}

Export-ModuleMember -Function `
    Get-QOTAppWhitelist, `
    Get-QOTInstalledApps, `
    Get-QOTAppRisk `
    -Variable QOT_AppWhitelistPatterns

