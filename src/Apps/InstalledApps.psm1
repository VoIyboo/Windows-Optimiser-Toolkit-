# src\Apps\InstalledApps.psm1
# Installed apps scanner for Apps tab

$ErrorActionPreference = "Stop"

function Test-QOTIsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) { return $false }
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-QOTWin32InstalledApps {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($path in $paths) {

        $items = @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            $name = ""
            try { $name = ("{0}" -f $item.DisplayName).Trim() } catch { $name = "" }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $publisher = ""
            try { $publisher = ("{0}" -f $item.Publisher).Trim() } catch { $publisher = "" }

            $version = ""
            try { $version = ("{0}" -f $item.DisplayVersion).Trim() } catch { $version = "" }

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

                    try { Write-QLog ("Error parsing InstallDate '{0}' for '{1}': {2}" -f $rawInstallDate, $name, $_.Exception.Message) "WARN" } catch { }
                }
            }

            $uninstall = $null
            if (-not [string]::IsNullOrWhiteSpace($item.QuietUninstallString)) {
                $uninstall = $item.QuietUninstallString
            }
            elseif (-not [string]::IsNullOrWhiteSpace($item.UninstallString)) {
                $uninstall = $item.UninstallString
            }


            $regKeyPath = $null
            try { $regKeyPath = $item.PSPath } catch { $regKeyPath = $null }

            $results.Add([pscustomobject]@{
                IsSelected      = $false
                Name            = $name
                Version         = $version
                Publisher       = $publisher
                Source          = "Win32"
                PackageName     = $null
                InstallDate     = $installDate

                UninstallString = $uninstall
                RegistryKeyPath = $regKeyPath

            })
        }
    }

    return @($results)
}

function Get-QOTStoreInstalledApps {
    param(
        [switch]$IncludeAllUsers
    )

    $results = New-Object System.Collections.Generic.List[object]

    $useAllUsers = $false
    if ($IncludeAllUsers -and (Test-QOTIsElevated)) {
        $useAllUsers = $true
    }
    $appxPackages = @()
    try {
        if ($useAllUsers) {
            $appxPackages = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
        }
        else {
            $appxPackages = @(Get-AppxPackage -ErrorAction Stop)
        }
    }
    catch {
        if ($useAllUsers) {
            try { Write-QLog ("Get-AppxPackage -AllUsers failed, falling back to current user: {0}" -f $_.Exception.Message) "WARN" } catch { }
            try { $appxPackages = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { $appxPackages = @() }
        }
        else {
            throw
        }
    }

    foreach ($appx in $appxPackages) {
        if (-not $appx) { continue }

        $name = ""
        try { $name = ("{0}" -f $appx.Name).Trim() } catch { $name = "" }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $publisher = ""
        try { $publisher = ("{0}" -f $appx.PublisherDisplayName).Trim() } catch { $publisher = "" }
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            try { $publisher = ("{0}" -f $appx.Publisher).Trim() } catch { $publisher = "" }
        }

        $version = $null
        try { $version = $appx.Version.ToString() } catch { $version = $null }

        $fullName = $null
        try { $fullName = $appx.PackageFullName } catch { $fullName = $null }

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
            Source          = "Store"
            PackageName     = $name
            InstallDate     = $null

            UninstallString = $uninstall
            RegistryKeyPath = if ($fullName) { "APPX:$fullName" } else { "APPX:$name" }
        })
    }

    return @($results)
}

function Get-QOTInstalledApps {
    [CmdletBinding()]
    param(
        [switch]$IncludeAllUsersStore
    )

    $scanErrors = New-Object System.Collections.Generic.List[string]

    try { Write-QLog "Starting installed apps scan" "INFO" } catch { }

    $win32Apps = @()
    try {
        $win32Apps = @(Get-QOTWin32InstalledApps)
    }
    catch {
        $scanErrors.Add($_.Exception.Message) | Out-Null
        try { Write-QLog ("Win32 app scan failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }


    $storeApps = @()
    try {
        $storeApps = @(Get-QOTStoreInstalledApps -IncludeAllUsers:$IncludeAllUsersStore)
    }
    catch {
        $scanErrors.Add($_.Exception.Message) | Out-Null
        try { Write-QLog ("Store app scan failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    $results = @($win32Apps + $storeApps | Sort-Object Name, Publisher, Version, Source -Unique | Sort-Object Name)

    try { Write-QLog ("Win32 found: {0}, Store found: {1}" -f $win32Apps.Count, $storeApps.Count) "INFO" } catch { }

    if ($results.Count -eq 0) {
        $reasons = New-Object System.Collections.Generic.List[string]

        if ($win32Apps.Count -eq 0) {
            if ($scanErrors | Where-Object { $_ -match "Win32|registry|access|denied|permission" }) {
                $reasons.Add("Win32 source returned 0 apps (permissions/registry access issue detected).") | Out-Null
            }
            else {
                $reasons.Add("Win32 source returned 0 apps (no uninstall entries found or access restricted).") | Out-Null
            }
        }

        if ($storeApps.Count -eq 0) {
            if ($scanErrors | Where-Object { $_ -match "Appx|Get-AppxPackage|access|denied|permission" }) {
                $reasons.Add("Store source returned 0 apps (Get-AppxPackage permissions/error).") | Out-Null
            }
            else {
                $reasons.Add("Store source returned 0 apps (no Appx packages found for current scope).") | Out-Null
            }
        }

        if ($scanErrors.Count -gt 0) {
            foreach ($err in $scanErrors) {
                if (-not [string]::IsNullOrWhiteSpace($err)) {
                    $reasons.Add("Source error: $err") | Out-Null
                }
            }
        }

        if ($reasons.Count -eq 0) {
            $reasons.Add("No source-level errors were reported, but combined dataset is empty.") | Out-Null
        }

        foreach ($reason in $reasons) {
            try { Write-QLog $reason "WARN" } catch { }
        }
    }

    foreach ($err in $scanErrors) {
        if ([string]::IsNullOrWhiteSpace($err)) { continue }
        try { Write-QLog ("Any scan errors: {0}" -f $err) "ERROR" } catch { }
    }

    return $results
}

function Get-QOTInstalledAppsCached {
    param(
        [switch]$ForceRefresh,
        [switch]$IncludeAllUsersStore
    )

    if (-not $ForceRefresh -and $Global:QOT_InstalledAppsCache -and $Global:QOT_InstalledAppsCache.Count -gt 0) {
        return @($Global:QOT_InstalledAppsCache)
    }

     $results = @(Get-QOTInstalledApps -IncludeAllUsersStore:$IncludeAllUsersStore)
    $Global:QOT_InstalledAppsCache = $results
    $Global:QOT_InstalledAppsCacheTimestamp = Get-Date
    return $results
}

Export-ModuleMember -Function Get-QOTInstalledApps, Get-QOTInstalledAppsCached, Get-QOTWin32InstalledApps, Get-QOTStoreInstalledApps
