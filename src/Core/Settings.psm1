# Settings.psm1
# Core settings persistence for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Repair-QOSettingsShape {
    param([Parameter(Mandatory)] $s)

    if (-not $s) { return $s }

    # Root level defaults
    if (-not ($s.PSObject.Properties.Name -contains "PreferredStartTab")) {
        $s | Add-Member -NotePropertyName PreferredStartTab -NotePropertyValue "Cleaning" -Force
    }
    if (-not ($s.PSObject.Properties.Name -contains "TicketsColumnLayout")) {
        $s | Add-Member -NotePropertyName TicketsColumnLayout -NotePropertyValue @() -Force
    }
    if (-not ($s.PSObject.Properties.Name -contains "TicketStorePath")) {
        $s | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $null -Force
    }
    if (-not ($s.PSObject.Properties.Name -contains "LocalTicketBackupPath")) {
        $s | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue $null -Force
    }

    # Tickets container
    if (-not ($s.PSObject.Properties.Name -contains "Tickets")) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    # EmailIntegration container
    if (-not ($s.Tickets.PSObject.Properties.Name -contains "EmailIntegration")) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    # Enabled
    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "Enabled")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName Enabled -NotePropertyValue $false -Force
    }

    # MonitoredAddresses (ALWAYS an array of strings)
    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    $ma = $s.Tickets.EmailIntegration.MonitoredAddresses
    if ($null -eq $ma) {
        $s.Tickets.EmailIntegration.MonitoredAddresses = @()
    }
    elseif ($ma -is [string]) {
        $trim = $ma.Trim()
        $s.Tickets.EmailIntegration.MonitoredAddresses = if ($trim) { @($trim) } else { @() }
    }
    else {
        $s.Tickets.EmailIntegration.MonitoredAddresses =
            @($ma) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    }

    # LastProcessedByMailbox (ensure it exists and is an object)
    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastProcessedByMailbox")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName LastProcessedByMailbox -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.LastProcessedByMailbox) {
        $s.Tickets.EmailIntegration.LastProcessedByMailbox = [pscustomobject]@{}
    }

    return $s
}

function Get-QOSettings {

    $defaults = [pscustomobject]@{
        PreferredStartTab     = "Cleaning"
        TicketsColumnLayout   = @()
        TicketStorePath       = $null
        LocalTicketBackupPath = $null
        Tickets              = [pscustomobject]@{
            EmailIntegration = [pscustomobject]@{
                Enabled              = $false
                MonitoredAddresses   = @()
                LastProcessedByMailbox = [pscustomobject]@{}
            }
        }
    }

    # First run
    if (-not (Test-Path -LiteralPath $script:QOSettingsPath)) {
        $dir = Split-Path $script:QOSettingsPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $defaults | ConvertTo-Json -Depth 8 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $defaults
    }

    # Read existing
    $json = Get-Content -Path $script:QOSettingsPath -Raw -ErrorAction SilentlyContinue
    if (-not $json) {
        return $defaults
    }

    $settings = $json | ConvertFrom-Json

    # IMPORTANT: always repair shape on load
    $settings = Repair-QOSettingsShape -s $settings

    return $settings
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $dir = Split-Path $script:QOSettingsPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings = Repair-QOSettingsShape -s $Settings

    $Settings | ConvertTo-Json -Depth 8 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
}

Export-ModuleMember -Function Get-QOSettings, Save-QOSettings
