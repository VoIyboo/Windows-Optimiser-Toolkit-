function Get-QOTInstalledApps {
    <#
        .SYNOPSIS
            Scans common registry locations for installed applications and returns normalised objects
            for the UI and engine.

        .NOTES
            Changes in this version:
            - Adds IsSelected for checkbox UI
            - Adds Version (DisplayVersion)
            - Captures RegistryKeyPath for troubleshooting
            - Improves system app filtering slightly but keeps your intent
            - Safer handling for null properties
            - Dedupes cleanly by Name + Publisher + Version (not just Name)
    #>

    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($path in $paths) {

        $items = @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)
        foreach ($item in $items) {

            $name = $item.DisplayName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $publisher = $item.Publisher
            $version   = $item.DisplayVersion

            # ----------------------------------------------------------------
            # System / noise filtering
            # ----------------------------------------------------------------
            $isSystem = $false

            if ($item.SystemComponent -eq 1) { $isSystem = $true }
            if (-not [string]::IsNullOrWhiteSpace($item.ReleaseType) -and $item.ReleaseType -eq "Security Update") { $isSystem = $true }
            if (-not [string]::IsNullOrWhiteSpace($item.ParentKeyName)) { $isSystem = $true }

            if ($name -match "(?i)\b(Driver|Runtime|Redistributable|Update|Hotfix)\b") { $isSystem = $true }
            if (-not [string]::IsNullOrWhiteSpace($publisher) -and $publisher -match "(?i)\b(Microsoft|Intel|NVIDIA|Realtek|AMD)\b") { $isSystem = $true }

            # ----------------------------------------------------------------
            # Size
            # ----------------------------------------------------------------
            $sizeMB = $null
            if ($item.EstimatedSize) {
                try { $sizeMB = [math]::Round(([double]$item.EstimatedSize) / 1024, 1) } catch { $sizeMB = $null }
            }

            # ----------------------------------------------------------------
            # Install Date
            # ----------------------------------------------------------------
            $installDate = $null
            $rawInstallDate = ""
            try { $rawInstallDate = ("{0}" -f $item.InstallDate).Trim() } catch { $rawInstallDate = "" }

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
                        )
                    ) {
                        $installDate = $parsed
                    }
                    elseif ([datetime]::TryParse(
                        $rawInstallDate,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None,
                        [ref]$parsed
                    )) {
                        $installDate = $parsed
                    }
                }
                catch {
                    try { Write-QLog "Error parsing InstallDate '$rawInstallDate' for $name: $($_.Exception.Message)" "WARN" } catch { }
                }
            }

            # ----------------------------------------------------------------
            # Whitelist
            # ----------------------------------------------------------------
            $isWhitelisted = $false
            if ($Global:QOT_AppWhitelistPatterns) {
                foreach ($pattern in $Global:QOT_AppWhitelistPatterns) {
                    if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
                    if ($name -like "*$pattern*") {
                        $isWhitelisted = $true
                        break
                    }
                }
            }

            # ----------------------------------------------------------------
            # Uninstall string fallbacks
            # ----------------------------------------------------------------
            $uninstall = $null
            if (-not [string]::IsNullOrWhiteSpace($item.QuietUninstallString)) {
                $uninstall = $item.QuietUninstallString
            }
            elseif (-not [string]::IsNullOrWhiteSpace($item.UninstallString)) {
                $uninstall = $item.UninstallString
            }

            # Record the registry key path for debugging and later improvements
            $regKeyPath = $null
            try { $regKeyPath = $item.PSPath } catch { $regKeyPath = $null }

            $results.Add([pscustomobject]@{
                IsSelected      = $false
                Name            = $name
                Version         = $version
                Publisher       = $publisher
                SizeMB          = $sizeMB
                InstallDate     = $installDate
                IsSystem        = $isSystem
                IsWhitelisted   = $isWhitelisted
                UninstallString = $uninstall
                RegistryKeyPath = $regKeyPath
                LastUsed        = $installDate
            })
        }
    }

    # Deduplicate more safely than just Name
    $results |
        Sort-Object Name, Publisher, Version -Unique |
        Sort-Object Name
}
