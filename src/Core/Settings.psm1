# src\Core\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Always save to THIS path
$script:SettingsPath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\settings.json"

function Get-QOSettingsPath {
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

    # Depth must be high enough for nested Tickets.EmailIntegration.*
    $json = $Settings | ConvertTo-Json -Depth 25
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
                MonitoredAddresses            = @()

                # If user has not picked a date, we treat it as "follow today"
                EmailSyncStartDate            = ""     # stored as yyyy-MM-dd
                EmailSyncStartDatePinned      = $false  # $true once user chooses one
            }
        }
    }

    if (-not $NoSave) {
        Save-QOSettings -Settings $settings
    }

    return $settings
}

function Get-QOSettings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return New-QODefaultSettings
    }

    try {
        $json = Get-Content -LiteralPath $script:SettingsPath -Raw -ErrorAction Stop
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

        if ($null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
        }

        if ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -notcontains "EmailSyncStartDate") {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDate -NotePropertyValue "" -Force
        }

        if ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -notcontains "EmailSyncStartDatePinned") {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $false -Force
        }

        return $settings
    }
    catch {
        # Backup corrupted file then recreate
        try {
            $backupName = "{0}.bak_{1}" -f $script:SettingsPath, (Get-Date -Format "yyyyMMddHHmmss")
            Copy-Item -LiteralPath $script:SettingsPath -Destination $backupName -ErrorAction SilentlyContinue
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
# Email sync start date (cutoff)
# If pinned is false, UI should display today's date and not save it.
# If pinned is true, we store a yyyy-MM-dd string and remember it.
# --------------------------------------------------------------------
function Get-QOEmailSyncStartDateState {
    $s = Get-QOSettings
    if (-not $s) { return [pscustomobject]@{ Pinned = $false; Date = $null; DateString = "" } }

    $pinned = $false
    $dateString = ""
    try { $pinned = [bool]$s.Tickets.EmailIntegration.EmailSyncStartDatePinned } catch { $pinned = $false }
    try { $dateString = [string]$s.Tickets.EmailIntegration.EmailSyncStartDate } catch { $dateString = "" }

    $dt = $null
    if ($pinned -and $dateString) {
        try { $dt = [datetime]::ParseExact($dateString, "yyyy-MM-dd", $null) } catch { $dt = $null }
    }

    return [pscustomobject]@{
        Pinned     = $pinned
        Date       = $dt
        DateString = $dateString
    }
}

function Set-QOEmailSyncStartDatePinned {
    param(
        [Parameter(Mandatory)][datetime]$Date
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $s.Tickets.EmailIntegration.EmailSyncStartDatePinned = $true
    $s.Tickets.EmailIntegration.EmailSyncStartDate = $Date.ToString("yyyy-MM-dd")

    Save-QOSettings -Settings $s

    return (Get-QOEmailSyncStartDateState)
}

function Clear-QOEmailSyncStartDate {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $s.Tickets.EmailIntegration.EmailSyncStartDatePinned = $false
    $s.Tickets.EmailIntegration.EmailSyncStartDate = ""

    Save-QOSettings -Settings $s

    return (Get-QOEmailSyncStartDateState)
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
    Get-QOSettings, `
    Save-QOSettings, `
    Set-QOSetting, `
    Get-QOSettingsPath, `
    New-QODefaultSettings, `
    Get-QOMonitoredMailboxAddresses, `
    Set-QOMonitoredMailboxAddresses, `
    Get-QOMonitoredAddresses, `
    Set-QOMonitoredAddresses, `
    Get-QOEmailSyncStartDateState, `
    Set-QOEmailSyncStartDatePinned, `
    Clear-QOEmailSyncStartDate
