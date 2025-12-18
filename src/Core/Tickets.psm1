# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Settings\Settings.psm1") -Force -ErrorAction Stop

$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

function Ensure-QOSettingProperty {
    param(
        [Parameter(Mandatory)] [object]$Settings,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $DefaultValue
    )

    if (-not $Settings) { throw "Settings object is null." }

    if ($Settings.PSObject.Properties.Name -notcontains $Name) {
        $Settings | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
    }

    return $Settings
}

function New-QODefaultTicketDatabase {
    [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }
}

function Initialize-QOTicketStorage {
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOSettings

    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketStorePath"        -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "LocalTicketBackupPath" -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketsColumnLayout"   -DefaultValue @()

    if ([string]::IsNullOrWhiteSpace([string]$settings.TicketStorePath)) {
        $defaultDir  = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
        $settings.TicketStorePath = (Join-Path $defaultDir "Tickets.json")
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath)) {
        $settings.LocalTicketBackupPath = (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups")
    }

    Save-QOSettings -Settings $settings

    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) { New-Item -ItemType Directory -Path $storeDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) { New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null }

    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        (New-QODefaultTicketDatabase) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

function Get-QOTickets {
    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) { return (New-QODefaultTicketDatabase) }

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        if (-not ($db.PSObject.Properties.Name -contains "SchemaVersion")) { $db | Add-Member -NotePropertyName "SchemaVersion" -NotePropertyValue 1 }
        if (-not ($db.PSObject.Properties.Name -contains "Tickets")) { $db | Add-Member -NotePropertyName "Tickets" -NotePropertyValue @() }

        if ($null -eq $db.Tickets) { $db.Tickets = @() } else { $db.Tickets = @($db.Tickets) }

        return $db
    }
    catch {
        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format "yyyyMMddHHmmss"))
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupName -ErrorAction SilentlyContinue
            }
        } catch { }

        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
        return $db
    }
}

function Save-QOTickets {
    param([Parameter(Mandatory)] $Database)

    Initialize-QOTicketStorage

    if ($null -eq $Database.Tickets) { $Database.Tickets = @() } else { $Database.Tickets = @($Database.Tickets) }

    try {
        if (Test-Path -LiteralPath $script:TicketStorePath) {
            $stamp = Get-Date -Format "yyyyMMddHHmmss"
            $backupFile = Join-Path $script:TicketBackupPath ("Tickets_{0}.json" -f $stamp)
            Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupFile -ErrorAction SilentlyContinue
        }
    } catch { }

    $Database | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
}

function New-QOTicket {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [string]$Status = "Open",
        [string]$Priority = "Normal"
    )

    $now = Get-Date

    [pscustomobject]@{
        Id       = ([guid]::NewGuid().ToString())
        Title    = $Title
        Created  = $now.ToString("yyyy-MM-dd HH:mm:ss")
        Status   = $Status
        Priority = $Priority
        Updated  = $now.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)] $Ticket)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Database $db
    return $Ticket
}

function Get-QOTicketById {
    param([Parameter(Mandatory)] [string]$Id)

    $db = Get-QOTickets
    foreach ($t in @($db.Tickets)) { if ([string]$t.Id -eq $Id) { return $t } }
    return $null
}

function Remove-QOTicket {
    param([Parameter(Mandatory)] [string]$Id)

    $db = Get-QOTickets
    $before = @($db.Tickets).Count
    $db.Tickets = @($db.Tickets | Where-Object { [string]$_.Id -ne $Id })
    Save-QOTickets -Database $db
    return (@($db.Tickets).Count -lt $before)
}

function Set-QOTicketStatus {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Status
    )

    $db = Get-QOTickets
    $changed = $false

    foreach ($t in @($db.Tickets)) {
        if ([string]$t.Id -eq $Id) {
            $t.Status  = $Status
            $t.Updated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $changed = $true
            break
        }
    }

    if ($changed) { Save-QOTickets -Database $db }
    return $changed
}

function Set-QOTicketTitle {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Title
    )

    $db = Get-QOTickets
    $changed = $false

    foreach ($t in @($db.Tickets)) {
        if ([string]$t.Id -eq $Id) {
            $t.Title   = $Title
            $t.Updated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $changed = $true
            break
        }
    }

    if ($changed) { Save-QOTickets -Database $db }
    return $changed
}

Export-ModuleMember -Function `
    Initialize-QOTicketStorage,
    New-QODefaultTicketDatabase,
    Get-QOTickets,
    Save-QOTickets,
    New-QOTicket,
    Add-QOTicket,
    Get-QOTicketById,
    Remove-QOTicket,
    Set-QOTicketStatus,
    Set-QOTicketTitle
