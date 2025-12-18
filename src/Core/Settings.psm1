# Settings.psm1
# Core settings persistence for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QODefaultSettings {
    return [PSCustomObject]@{
        PreferredStartTab     = "Cleaning"
        TicketsColumnLayout   = @()
        TicketStorePath       = $null
        LocalTicketBackupPath = $null

        Tickets = [PSCustomObject]@{
            EmailIntegration = [PSCustomObject]@{
                Enabled               = $false
                MonitoredAddresses    = @()
                LastProcessedByMailbox = @{}
            }
        }
    }
}

function Repair-QOSettingsShape {
    param([Parameter(Mandatory)] $s)

    if (-not $s) { return $s }

    $defaults = Get-QODefaultSettings

    foreach ($p in @("PreferredStartTab","TicketsColumnLayout","TicketStorePath","LocalTicketBackupPath")) {
        if (-not ($s.PSObject.Properties.Name -contains $p)) {
            $s | Add-Member -NotePropertyName $p -NotePropertyValue $defaults.$p -Force
        }
    }

    if (-not ($s.PSObject.Properties.Name -contains "Tickets")) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($s.Tickets.PSObject.Properties.Name -contains "EmailIntegration")) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "Enabled")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName Enabled -NotePropertyValue $false -Force
    }
    $s.Tickets.EmailIntegration.Enabled = [bool]$s.Tickets.EmailIntegration.Enabled

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

    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastProcessedByMailbox")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName LastProcessedByMailbox -NotePropertyValue @{} -Force
    }

    $lpm = $s.Tickets.EmailIntegration.LastProcessedByMailbox

    if ($null -eq $lpm) {
        $s.Tickets.EmailIntegration.LastProcessedByMailbox = @{}
    }
    elseif ($lpm -is [string]) {
        $s.Tickets.EmailIntegration.LastProcessedByMailbox = @{}
    }
    elseif ($lpm -is [System.Collections.IDictionary]) {
        # ok
    }
    else {
        # PSCustomObject -> hashtable
        $ht = @{}
        foreach ($p in $lpm.PSObject.Properties) {
            if ($p.Name) { $ht[$p.Name] = $p.Value }
        }
        $s.Tickets.EmailIntegration.LastProcessedByMailbox = $ht
    }

    return $s
}

function Get-QOSettings {

    $defaults = Get-QODefaultSettings

    if (-not (Test-Path $script:QOSettingsPath)) {
        $dir = Split-Path $script:QOSettingsPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $defaults | ConvertTo-Json -Depth 8 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $defaults
    }

    $json = Get-Content -Path $script:QOSettingsPath -Raw -ErrorAction SilentlyContinue
    if (-not $json) {
        return $defaults
    }

    try {
        $settings = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Backup the broken file and recreate clean defaults
        try {
            $dir = Split-Path $script:QOSettingsPath
            $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
            $backup = Join-Path $dir ("Settings.broken.{0}.json" -f $stamp)
            Copy-Item -Path $script:QOSettingsPath -Destination $backup -Force -ErrorAction SilentlyContinue
        } catch { }

        $defaults | ConvertTo-Json -Depth 8 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $defaults
    }

    $settings = Repair-QOSettingsShape -s $settings
    return $settings
}

function Save-QOSettings {
    param([Parameter(Mandatory)] $Settings)

    $dir = Split-Path $script:QOSettingsPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings = Repair-QOSettingsShape -s $Settings
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
}



function Get-QOMonitoredEmailAddresses {
    $s = Get-QOSettings
    if ($s -and $s.Tickets -and $s.Tickets.EmailIntegration) {
        return @($s.Tickets.EmailIntegration.MonitoredAddresses)
    }
    return @()
}

function Add-QOMonitoredEmailAddress {
    param([Parameter(Mandatory)][string]$Address)

    $addr = $Address.Trim()
    if ([string]::IsNullOrWhiteSpace($addr)) { return $false }

    $s = Get-QOSettings
    $list = @($s.Tickets.EmailIntegration.MonitoredAddresses)

    if ($list -contains $addr) { return $false }

    $s.Tickets.EmailIntegration.MonitoredAddresses = @($list + $addr | Select-Object -Unique)
    Save-QOSettings -Settings $s
    return $true
}

function Remove-QOMonitoredEmailAddress {
    param([Parameter(Mandatory)][string]$Address)

    $addr = $Address.Trim()
    if ([string]::IsNullOrWhiteSpace($addr)) { return $false }

    $s = Get-QOSettings
    $list = @($s.Tickets.EmailIntegration.MonitoredAddresses)

    $new = @($list | Where-Object { $_ -ne $addr })
    $changed = ($new.Count -ne $list.Count)

    if ($changed) {
        $s.Tickets.EmailIntegration.MonitoredAddresses = $new
        Save-QOSettings -Settings $s
    }

    return $changed
}


Export-ModuleMember -Function Get-QOSettings, Save-QOSettings
