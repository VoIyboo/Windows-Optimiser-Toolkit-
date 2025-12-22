# src\Core\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Path to the settings JSON file in AppData
$script:SettingsPath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\settings.json"

function Get-QOSettingsPath {
    return $script:SettingsPath
}

function New-QODefaultSettings {
    param(
        [switch]$NoSave
    )

    $settings = [pscustomobject]@{
        SchemaVersion         = 1
        TicketStorePath       = ""
        LocalTicketBackupPath = ""
        PreferredStartTab     = "Cleaning"   # Cleaning | Apps | Advanced | Tickets
        InternalProtectionKey = $null

        TicketsColumnLayout   = @()

        # IMPORTANT: include this structure so it round-trips properly
        Tickets = [pscustomobject]@{
            EmailIntegration = [pscustomobject]@{
                MonitoredAddresses = @()
            }
        }
    }

    $dir = Split-Path -Parent $script:SettingsPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not $NoSave) {
        $json = $settings | ConvertTo-Json -Depth 20
        Set-Content -LiteralPath $script:SettingsPath -Value $json -Encoding UTF8
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

        # Merge missing defaults (including nested objects)
        $defaults = New-QODefaultSettings -NoSave

        foreach ($prop in $defaults.PSObject.Properties.Name) {
            if (-not ($settings.PSObject.Properties.Name -contains $prop)) {
                $settings | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.$prop -Force
            }
        }

        if (-not $settings.Tickets) {
            $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue $defaults.Tickets -Force
        }

        if (-not $settings.Tickets.EmailIntegration) {
            $settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue $defaults.Tickets.EmailIntegration -Force
        }

        if ($null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
        }

        return $settings
    }
    catch {
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

    $dir = Split-Path -Parent $script:SettingsPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Settings | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $script:SettingsPath -Value $json -Encoding UTF8
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

Export-ModuleMember -Function Get-QOSettingsPath, Get-QOSettings, New-QODefaultSettings, Save-QOSettings, Set-QOSetting
