    # Settings.psm1
# Core settings persistence for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QOSettings {

    if (-not (Test-Path $script:QOSettingsPath)) {

        $default = [PSCustomObject]@{
            PreferredStartTab     = "Cleaning"
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null

            Tickets = [PSCustomObject]@{
                EmailIntegration = [PSCustomObject]@{
                    Enabled            = $false
                    MonitoredAddresses = @()
                }
            }
        }

        $dir = Split-Path $script:QOSettingsPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $default | ConvertTo-Json -Depth 6 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $default
    }

    $json = Get-Content -Path $script:QOSettingsPath -Raw -ErrorAction SilentlyContinue
    if (-not $json) {
        return [PSCustomObject]@{
            PreferredStartTab     = "Cleaning"
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }
    }

    $settings = $json | ConvertFrom-Json

    if (-not ($settings.PSObject.Properties.Name -contains "PreferredStartTab")) {
        $settings | Add-Member -NotePropertyName PreferredStartTab -NotePropertyValue "Cleaning"
    }
    if (-not ($settings.PSObject.Properties.Name -contains "TicketsColumnLayout")) {
        $settings | Add-Member -NotePropertyName TicketsColumnLayout -NotePropertyValue @()
    }
    if (-not ($settings.PSObject.Properties.Name -contains "TicketStorePath")) {
        $settings | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $null
    }
    if (-not ($settings.PSObject.Properties.Name -contains "LocalTicketBackupPath")) {
        $settings | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue $null
    }

    return $settings
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $dir = Split-Path $script:QOSettingsPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 6 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
}

Export-ModuleMember -Function Get-QOSettings, Save-QOSettings
