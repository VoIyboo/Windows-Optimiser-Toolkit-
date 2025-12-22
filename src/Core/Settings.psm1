# src\Core\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Always save to THIS path
$script:SettingsPath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\settings.json"

function Get-QOSettingsPath {
    return $script:SettingsPath
}

function Ensure-QOTicketsEmailIntegration {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    if (-not $Settings) {
        $Settings = [pscustomobject]@{}
    }

    if (-not $Settings.Tickets) {
        $Settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not $Settings.Tickets.EmailIntegration) {
        $Settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if ($null -eq $Settings.Tickets.EmailIntegration.MonitoredAddresses) {
        $Settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    return $Settings
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
                MonitoredAddresses = @()
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

        # Ensure nested structure exists (Tickets.EmailIntegration.MonitoredAddresses)
        $settings = Ensure-QOTicketsEmailIntegration -Settings $settings

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

    # Always ensure nested structure before writing
    $Settings = Ensure-QOTicketsEmailIntegration -Settings $Settings

    # Depth must be high enough for nested objects
    $json = $Settings | ConvertTo-Json -Depth 20

    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
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

function Set-QOMonitoredAddresses {
    param(
        [Parameter(Mandatory)]
        [string[]]$Addresses
    )

    $settings = Get-QOSettings
    if (-not $settings) { $settings = New-QODefaultSettings -NoSave }

    $settings = Ensure-QOTicketsEmailIntegration -Settings $settings

    $clean = @(
        $Addresses |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ } |
        Select-Object -Unique
    )

    $settings.Tickets.EmailIntegration.MonitoredAddresses = $clean
    Save-QOSettings -Settings $settings

    return $settings
}

Export-ModuleMember -Function `
    Get-QOSettings, `
    Save-QOSettings, `
    Set-QOSetting, `
    Get-QOSettingsPath, `
    New-QODefaultSettings, `
    Set-QOMonitoredAddresses
