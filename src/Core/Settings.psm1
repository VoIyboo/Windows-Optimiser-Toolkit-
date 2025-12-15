# Settings.psm1
# Core settings persistence for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QOSettings {

    # ------------------------------
    # Defaults (single source of truth)
    # ------------------------------
    $defaults = [PSCustomObject]@{
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

    # ------------------------------
    # First run: create settings.json
    # ------------------------------
    if (-not (Test-Path $script:QOSettingsPath)) {

        $dir = Split-Path $script:QOSettingsPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $defaults | ConvertTo-Json -Depth 6 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $defaults
    }

    # ------------------------------
    # Read existing settings.json
    # ------------------------------
    $json = Get-Content -Path $script:QOSettingsPath -Raw -ErrorAction SilentlyContinue
    if (-not $json) {
        return $defaults
    }

    $settings = $json | ConvertFrom-Json

    # ------------------------------
    # Backward compatibility guards
    # ------------------------------
    if (-not ($settings.PSObject.Properties.Name -contains "PreferredStartTab")) {
        $settings | Add-Member -NotePropertyName PreferredStartTab -NotePropertyValue $defaults.PreferredStartTab
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

    # Tickets.EmailIntegration (email-to-ticket)
    if (-not ($settings.PSObject.Properties.Name -contains "Tickets")) {
        $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{})
    }

    if (-not ($settings.Tickets.PSObject.Properties.Name -contains "EmailIntegration")) {
        $settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{})
    }

    if (-not ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "Enabled")) {
        $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName Enabled -NotePropertyValue $false
    }

    if (-not ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
        $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @()
    }

    # Ensure MonitoredAddresses is always an array
    if ($null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
        $settings.Tickets.EmailIntegration.MonitoredAddresses = @()
    }
    elseif ($settings.Tickets.EmailIntegration.MonitoredAddresses -is [string]) {
        $settings.Tickets.EmailIntegration.MonitoredAddresses = @($settings.Tickets.EmailIntegration.MonitoredAddresses)
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
