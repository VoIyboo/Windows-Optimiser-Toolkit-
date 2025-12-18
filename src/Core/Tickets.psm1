# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

# Only import Settings here
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

# =====================================================================
# Script state
# =====================================================================
$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

# =====================================================================
# Helpers
# =====================================================================
function Ensure-QOSettingProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Settings,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        $DefaultValue
    )

    if (-not $Settings) { throw "Settings object is null." }

    if ($Settings.PSObject.Properties.Name -notcontains $Name) {
        $Settings | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
    }

    return $Settings
}

function New-QODefaultTicketDatabase {
    return [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }
}

function New-QOGuid {
    return ([guid]::NewGuid().ToString())
}

# =====================================================================
# Storage initialisation
# =====================================================================
function Initialize-QOTicketStorage {
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOSettings

    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketStorePath" -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "LocalTicketBackupPath" -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketsColumnLayout" -DefaultValue @()

    if ([string]::IsNullOrWhiteSpace([string]$settings.TicketStorePath)) {
        $defaultTicketsDir  = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
        $defaultTicketsFile = Join-Path $defaultTicketsDir "Tickets.json"
        $settings.TicketStorePath = $defaultTicketsFile
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath)) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups"
        $settings.LocalTicketBackupPath = $defaultBackupDir
    }

    Save-QOSettings -Settings $settings

    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

# =====================================================================
# Database IO
# =====================================================================
function Get-QOTickets {
    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultTicketDatabase
        }

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        if (-not $db.PSObject.Properties.Name.Contains("SchemaVersion")) {
            $db | Add-Member -NotePropertyName "SchemaVersion" -NotePropertyValue 1
        }
        if (-not $db.PSObject.Properties.Name.Contains("Tickets")) {
            $db | Add-Member -NotePropertyName "Tickets" -NotePropertyValue @()
        }

        if ($null -eq $db.Tickets) {
            $db.Tickets = @()
        } else {
            $db.Tickets = @($db.Tickets)
        }

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
    param(
        [Parameter(Mandatory)]
        $Database
    )

    Initialize-QOTicketStorage

    if (-not $Database) { throw "Save-QOTickets: Database is null." }

    if (-not ($Database.PSObject.Properties.Name -contains "SchemaVersion")) {
        $Database | Add-Member -NotePropertyName "SchemaVersion" -NotePropertyValue 1
    }
    if (-not ($Database.PSObject.Properties.Name -contains "Tickets")) {
        $Database | Add-Member -NotePropertyName "Tickets" -NotePropertyValue @()
    }

    if ($null -eq $Database.Tickets) {
        $Database.Tickets = @()
    } else {
        $Database.Tickets = @($Database.Tickets)
    }

    try {
        if (Test-Path -LiteralPath $script:TicketStorePath) {
            $stamp = Get-Date -Format "yyyyMMddHHmmss"
            $backupFile = Join-Path $script:TicketBackupPath ("Tickets_{0}.json" -f $stamp)
            Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupFile -ErrorAction SilentlyContinue
        }
    } catch { }

    $Database | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
}

# =====================================================================
# Ticket model + CRUD
# =====================================================================
function New-QOTicket {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Status  = "Open",
        [string]$Priority = "Normal",

        [string]$Source = "Manual"
    )

    $now = Get-Date

    return [pscustomobject]@{
        Id        = (New-QOGuid)
        Title     = $Title
        Created   = $now.ToString("yyyy-MM-dd HH:mm:ss")
        Status    = $Status
        Priority  = $Priority
        Source    = $Source

        # Future-friendly fields (safe to ignore in UI)
        Updated   = $now.ToString("yyyy-MM-dd HH:mm:ss")
        Notes     = ""
        Tags      = @()
    }
}

function Add-QOTicket {
    param(
        [Parameter(Mandatory)]
        $Ticket
    )

    $db = Get-QOTickets

    if ($null -eq $db.Tickets) { $db.Tickets = @() }

    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Database $db
    return $Ticket
}

function Get-QOTicketById {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $db = Get-QOTickets
    foreach ($t in @($db.Tickets)) {
        if ([string]$t.Id -eq $Id) { return $t }
    }
    return $null
}

function Remove-QOTicket {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $db = Get-QOTickets
    $before = @($db.Tickets).Count

    $db.Tickets = @($db.Tickets | Where-Object { [string]$_.Id -ne $Id })

    Save-QOTickets -Database $db

    $after = @($db.Tickets).Count
    return ($after -lt $before)
}

function Set-QOTicketStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Status
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
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Title
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

# =====================================================================
# Export
# =====================================================================
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
