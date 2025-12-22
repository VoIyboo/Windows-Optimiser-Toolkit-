# src\Core\Settings\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Path to the settings JSON file in AppData
$script:SettingsPath = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\settings.json'

function Get-QOSettingsPath {
    return $script:SettingsPath
}

function New-QODefaultSettings {
    param(
        [switch]$NoSave
    )

    $settings = [pscustomobject]@{
        SchemaVersion          = 1
        TicketStorePath        = ""
        LocalTicketBackupPath  = ""
        PreferredStartTab      = "Cleaning"
        InternalProtectionKey  = $null

        TicketsColumnLayout    = @()

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
        $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    }

    return $settings
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $path = $script:SettingsPath

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Settings | ConvertTo-Json -Depth 20

    # Force overwrite
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8 -Force

    # Debug proof
    if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
        Write-QLog "Save-QOSettings wrote to: $path"
    }
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

        # Merge defaults (adds any missing props)
        $defaults = New-QODefaultSettings -NoSave
        foreach ($prop in $defaults.PSObject.Properties.Name) {
            if (-not $settings.PSObject.Properties.Name.Contains($prop)) {
                $settings | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.$prop -Force
            }
        }

        # Ensure Tickets.EmailIntegration.MonitoredAddresses exists
        if (-not ($settings.PSObject.Properties.Name -contains "Tickets") -or -not $settings.Tickets) {
            $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not ($settings.Tickets.PSObject.Properties.Name -contains "EmailIntegration") -or -not $settings.Tickets.EmailIntegration) {
            $settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses") -or $null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
        }

        return $settings
    }
    catch {
        # Settings file is corrupted, back it up and recreate
        try {
            $backupName = '{0}.bak_{1}' -f $script:SettingsPath, (Get-Date -Format 'yyyyMMddHHmmss')
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

Export-ModuleMember -Function Get-QOSettingsPath, Get-QOSettings, New-QODefaultSettings, Save-QOSettings, Set-QOSetting
