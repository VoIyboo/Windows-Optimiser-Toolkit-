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
            $rawInstallDate = ($_.InstallDate | ForEach-Object { "$_".Trim() })

            if (-not [string]::IsNullOrWhiteSpace($rawInstallDate)) {
                $parsed = [datetime]::MinValue
                try {
                    if ($rawInstallDate -match '^\d{8}$' -and
                        [datetime]::TryParseExact(
                            $rawInstallDate,
                            'yyyyMMdd',
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::None,
                            [ref]$parsed
                        )) {
                        $installDate = $parsed
                    } else {
                        if ([datetime]::TryParse(
                            $rawInstallDate,
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::None,
                            [ref]$parsed
                        )) {
                            $installDate = $parsed
                        }
                    }
                }
                catch {
                    try { Write-QLog "Error parsing InstallDate '$rawInstallDate' for $($_.DisplayName): $($_.Exception.Message)" "WARN" } catch { }
                }
            }

            $isWhitelisted = $false
            foreach ($pattern in $Global:QOT_AppWhitelistPatterns) {
                if ($_.DisplayName -like "*$pattern*") {
                    $isWhitelisted = $true
                    break
                }
            }

            # Uninstall string fallbacks (a lot of apps only have QuietUninstallString)
            $uninstall = $null
            if ($_.QuietUninstallString) {
                $uninstall = $_.QuietUninstallString
            } elseif ($_.UninstallString) {
                $uninstall = $_.UninstallString
            }

            [PSCustomObject]@{
                Name            = $_.DisplayName
                Publisher       = $_.Publisher
                SizeMB          = $sizeMB
                InstallDate     = $installDate
                IsSystem        = $isSystem
                IsWhitelisted   = $isWhitelisted
                UninstallString = $uninstall
                LastUsed        = $installDate
            }
        }
    }

    $apps | Sort-Object Name -Unique
}
