# ------------------------------
# App scan and risk logic
# ------------------------------
$Global:AppWhitelistPatterns = @(
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

function Get-InstalledApps {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $_.DisplayName) { continue }

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
                        Write-Log "Invalid InstallDate '$($_.InstallDate)' for $($_.DisplayName)" "WARN"
                    }
                }
                catch {
                    Write-Log "Error parsing InstallDate '$($_.InstallDate)' for $($_.DisplayName): $($_.Exception.Message)" "WARN"
                }
            }

            $isWhitelisted = $false
            foreach ($pattern in $Global:AppWhitelistPatterns) {
                if ($_.DisplayName -like "*$pattern*") { $isWhitelisted = $true; break }
            }

            [PSCustomObject]@{
                Name            = $_.DisplayName
                Publisher       = $_.Publisher
                SizeMB          = $sizeMB
                InstallDate     = $installDate
                IsSystem        = $isSystem
                IsWhitelisted   = $isWhitelisted
                UninstallString = $_.UninstallString
                LastUsed        = $installDate
            }
        }
    }

    $apps | Sort-Object Name -Unique
}

function Get-AppRisk {
    param($App)

    if ($App.IsWhitelisted) { return "Protected" }
    if ($App.IsSystem -or -not $App.UninstallString) { return "Red" }

    $days = $null
    if ($App.InstallDate) {
        $days = (New-TimeSpan -Start $App.InstallDate -End (Get-Date)).Days
    }

    if ($App.SizeMB -ge 500 -or $days -ge 365) { return "Amber" }
    return "Green"
}

# QOT.Apps.psm1
# App scan and risk helpers for legacy v2.7

$Global:AppWhitelistPatterns = @(
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

function Get-InstalledApps {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $_.DisplayName) { continue }

            $isSystem = $false
            if ($_.SystemComponent -eq 1) { $isSystem = $true }
            if ($_.ReleaseType -eq "Security Update" -or $_.ParentKeyName) { $isSystem = $true }
            if ($_.DisplayName -match "Driver|Runtime|Redistributable|Update|Hotfix") { $isSystem = $true }
            if ($_.Publisher -match "Microsoft|Intel|NVIDIA|Realtek|AMD") { $isSystem = $true }

            $sizeMB = $null
            if ($_.EstimatedSize) { $sizeMB = [math]::Round($_.EstimatedSize / 1024, 1) }

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
                        Write-Log "Invalid InstallDate '$($_.InstallDate)' for $($_.DisplayName)" "WARN"
                    }
                }
                catch {
                    Write-Log "Error parsing InstallDate '$($_.InstallDate)' for $($_.DisplayName): $($_.Exception.Message)" "WARN"
                }
            }

            $isWhitelisted = $false
            foreach ($pattern in $Global:AppWhitelistPatterns) {
                if ($_.DisplayName -like "*$pattern*") { $isWhitelisted = $true; break }
            }

            [PSCustomObject]@{
                Name            = $_.DisplayName
                Publisher       = $_.Publisher
                SizeMB          = $sizeMB
                InstallDate     = $installDate
                IsSystem        = $isSystem
                IsWhitelisted   = $isWhitelisted
                UninstallString = $_.UninstallString
                LastUsed        = $installDate
            }
        }
    }

    $apps | Sort-Object Name -Unique
}

function Get-AppRisk {
    param($App)

    if ($App.IsWhitelisted) { return "Protected" }
    if ($App.IsSystem -or -not $App.UninstallString) { return "Red" }

    $days = $null
    if ($App.InstallDate) {
        $days = (New-TimeSpan -Start $App.InstallDate -End (Get-Date)).Days
    }

    if ($App.SizeMB -ge 500 -or $days -ge 365) { return "Amber" }
    return "Green"
}

Export-ModuleMember -Function Get-InstalledApps, Get-AppRisk -Variable AppWhitelistPatterns
