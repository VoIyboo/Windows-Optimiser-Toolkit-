# src\Apps\InstalledApps.psm1
# Installed apps scanner for Apps tab

$ErrorActionPreference = "Stop"

function Get-QOTInstalledApps {
    <#
        .SYNOPSIS
            Scans common registry locations for installed applications and returns normalised objects
            for the UI and engine.

        .NOTES
            - Adds IsSelected for checkbox UI
            - Adds Version (DisplayVersion)
            - Captures RegistryKeyPath for troubleshooting
            - Safer handling for null properties
            - Dedupes by Name + Publisher + Version
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
                    # Avoid "$name:" in strings, it parses like a drive reference
                    try { Write-QLog ("Error parsing InstallDate '{0}' for '{1}': {2}" -f $rawInstallDate, $name, $_.Exception.Message) "WARN" } catch { }
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

            # Registry key path for debugging
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

        # ----------------------------------------------------------------
    # Appx (Store) packages
    # ----------------------------------------------------------------
    $appxPackages = @()
    try {
        $appxPackages = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    }
    catch {
        try { $appxPackages = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { $appxPackages = @() }
        try { Write-QLog ("Get-AppxPackage -AllUsers failed, falling back to current user: {0}" -f $_.Exception.Message) "WARN" } catch { }
    }

    foreach ($appx in $appxPackages) {
        if (-not $appx) { continue }

        $name = $appx.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $publisher = $appx.PublisherDisplayName
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            $publisher = $appx.Publisher
        }

        $version = $null
        try { $version = $appx.Version.ToString() } catch { $version = $null }

        $isSystem = $false
        try {
            if ($appx.IsFramework -or $appx.IsResourcePackage) { $isSystem = $true }
        } catch { }

        $fullName = $appx.PackageFullName
        $uninstall = $null
        if (-not [string]::IsNullOrWhiteSpace($fullName)) {
            $escaped = $fullName.Replace("'", "''")
            $uninstall = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Remove-AppxPackage -Package '$escaped'`""
        }

        $results.Add([pscustomobject]@{
            IsSelected      = $false
            Name            = $name
            Version         = $version
            Publisher       = $publisher
            SizeMB          = $null
            InstallDate     = $null
            IsSystem        = $isSystem
            IsWhitelisted   = $false
            UninstallString = $uninstall
            RegistryKeyPath = "APPX:$fullName"
            LastUsed        = $null
        })
    }

    $results |
        Sort-Object Name, Publisher, Version -Unique |
        Sort-Object Name
}

Export-ModuleMember -Function Get-QOTInstalledApps
