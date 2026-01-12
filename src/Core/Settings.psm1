# src\Core\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Always save to THIS path (resolved lazily)
$script:SettingsPath = $null

function Get-QOAppDataRoot {
    $candidates = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:USERPROFILE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    if ($candidates.Count -gt 0) {
        return [string]$candidates[0]
    }

    return [System.IO.Path]::GetTempPath()
}

function Get-QOSettingsPath {
    if (-not $script:SettingsPath) {
        $script:SettingsPath = Join-Path (Get-QOAppDataRoot) "StudioVoly\QuinnToolkit\settings.json"
    }
    return $script:SettingsPath
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $path = Get-QOSettingsPath

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Depth must be high enough for nested structures
    $json = $Settings | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function New-QODefaultSettings {
    param(
        [switch]$NoSave
    )

    $settings = [pscustomobject]@{
        SchemaVersion         = 1
        TicketStorePath       = ""
        LocalTicketBackupPath = ""
        PreferredStartTab     = "Cleaning"
        InternalProtectionKey = $null

        TicketsColumnLayout   = @()

        Tickets = [pscustomobject]@{
            EmailIntegration = [pscustomobject]@{
                MonitoredAddresses        = @()

                # If this is null or empty, UI follows today automatically.
                # When pinned, store as yyyy-MM-dd (date only, no time).
                EmailSyncStartDatePinned  = $null
            }
            StatusFilters = [pscustomobject]@{
                New             = $true
                InProgress      = $true
                WaitingOnUser   = $true
                NoLongerRequired = $true
                Completed       = $true
                IncludeDeleted  = $false
            }
        }
    }

    if (-not $NoSave) {
        Save-QOSettings -Settings $settings
    }

    return $settings
}

function Get-QOSettings {
    $path = Get-QOSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return New-QODefaultSettings
    }

    try {
        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultSettings
        }

        $settings = $json | ConvertFrom-Json -ErrorAction Stop

        # Merge defaults so missing keys get added
        $defaults = New-QODefaultSettings -NoSave

        foreach ($prop in $defaults.PSObject.Properties.Name) {
            if (-not $settings.PSObject.Properties.Name.Contains($prop)) {
                $settings | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.$prop -Force
            }
        }

        # Ensure nested structure exists
        if (-not $settings.Tickets) {
            $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue $defaults.Tickets -Force
        }

        if (-not $settings.Tickets.EmailIntegration) {
            $settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue $defaults.Tickets.EmailIntegration -Force
        }

        if (-not $settings.Tickets.StatusFilters) {
            $settings.Tickets | Add-Member -NotePropertyName StatusFilters -NotePropertyValue $defaults.Tickets.StatusFilters -Force
        }


        if ($null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
        }

        if ($null -eq $settings.Tickets.EmailIntegration.EmailSyncStartDatePinned) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $null -Force
        }

        foreach ($prop in $defaults.Tickets.StatusFilters.PSObject.Properties.Name) {
            if ($settings.Tickets.StatusFilters.PSObject.Properties.Name -notcontains $prop) {
                $settings.Tickets.StatusFilters | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.Tickets.StatusFilters.$prop -Force
            }
        }


        return $settings
    }
    catch {
        # Backup corrupted file then recreate
        try {
            $backupName = "{0}.bak_{1}" -f $path, (Get-Date -Format "yyyyMMddHHmmss")
            Copy-Item -LiteralPath $path -Destination $backupName -ErrorAction SilentlyContinue
        } catch { }

        return New-QODefaultSettings
    }
}

function Set-QOSetting {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Value
    )

    $settings = Get-QOSettings

    if ($settings.PSObject.Properties.Name -notcontains $Name) {
        $settings | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    } else {
        $settings.$Name = $Value
    }

    Save-QOSettings -Settings $settings
    return $settings
}

# --------------------------------------------------------------------
# Canonical API for monitored mailbox addresses
# Storage: Tickets.EmailIntegration.MonitoredAddresses
# --------------------------------------------------------------------
function Get-QOMonitoredMailboxAddresses {
    $s = Get-QOSettings
    if (-not $s) { return @() }

    $list = @()
    try { $list = @($s.Tickets.EmailIntegration.MonitoredAddresses) } catch { $list = @() }

    return @(
        $list |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )
}

function Set-QOMonitoredMailboxAddresses {
    param(
        [Parameter(Mandatory)]
        [string[]]$Addresses
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.MonitoredAddresses) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    $clean = @(
        $Addresses |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )

    $s.Tickets.EmailIntegration.MonitoredAddresses = $clean
    Save-QOSettings -Settings $s

    return $clean
}

# --------------------------------------------------------------------
# Email sync start date pinning
# Storage: Tickets.EmailIntegration.EmailSyncStartDatePinned (yyyy-MM-dd or null)
# --------------------------------------------------------------------
function Get-QOEmailSyncStartDatePinned {
    $s = Get-QOSettings
    if (-not $s) { return $null }

    try {
        $raw = [string]$s.Tickets.EmailIntegration.EmailSyncStartDatePinned
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

        # Date only, treat as local date
        return [datetime]::ParseExact($raw, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

function Set-QOEmailSyncStartDatePinned {
    param(
        [Parameter(Mandatory)]
        [datetime]$Date
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.EmailSyncStartDatePinned) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $null -Force
    }

    $s.Tickets.EmailIntegration.EmailSyncStartDatePinned = $Date.Date.ToString("yyyy-MM-dd")
    Save-QOSettings -Settings $s

    return (Get-QOEmailSyncStartDatePinned)
}

function Clear-QOEmailSyncStartDatePinned {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.EmailSyncStartDatePinned) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $null -Force
    }

    $s.Tickets.EmailIntegration.EmailSyncStartDatePinned = $null
    Save-QOSettings -Settings $s
    return $null
}

function Get-QOEffectiveEmailSyncStartDate {
    $pinned = Get-QOEmailSyncStartDatePinned
    if ($pinned) { return $pinned.Date }
    return (Get-Date).Date
}

# --------------------------------------------------------------------
# Compatibility wrappers (because UI/Tickets code may call these names)
# --------------------------------------------------------------------
function Set-QOMonitoredAddresses {
    param(
        [Parameter(Mandatory)]
        [string[]]$Addresses
    )
    return (Set-QOMonitoredMailboxAddresses -Addresses $Addresses)
}

function Get-QOMonitoredAddresses {
    return (Get-QOMonitoredMailboxAddresses)
}

Export-ModuleMember -Function `
    Get-QOAppDataRoot, `
    Get-QOSettings, `
    Save-QOSettings, `
    Set-QOSetting, `
    Get-QOSettingsPath, `
    New-QODefaultSettings, `
    Get-QOMonitoredMailboxAddresses, `
    Set-QOMonitoredMailboxAddresses, `
    Get-QOMonitoredAddresses, `
    Set-QOMonitoredAddresses, `
    Get-QOEmailSyncStartDatePinned, `
    Set-QOEmailSyncStartDatePinned, `
    Clear-QOEmailSyncStartDatePinned, `
    Get-QOEffectiveEmailSyncStartDate
