# Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System

# Import Settings module (even though we have local helpers here)
Import-Module "$PSScriptRoot\Settings.psm1" -Force

# =====================================================================
# SETTINGS ENGINE (LOCAL TO TICKETS MODULE)
# =====================================================================

# Path for settings.json
$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QOSettings {
    if (-not (Test-Path $script:QOSettingsPath)) {

        $default = [PSCustomObject]@{
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
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
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }
    }

    $settings = $json | ConvertFrom-Json

    if (-not $settings.PSObject.Properties.Name -contains 'TicketsColumnLayout') {
        $settings | Add-Member -NotePropertyName TicketsColumnLayout -NotePropertyValue @()
    }
    if (-not $settings.PSObject.Properties.Name -contains 'TicketStorePath') {
        $settings | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $null
    }
    if (-not $settings.PSObject.Properties.Name -contains 'LocalTicketBackupPath') {
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

# =====================================================================
# TICKET STORAGE PATHS
# =====================================================================

$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

function Initialize-QOTicketStorage {

    if ($script:TicketStorePath -and $script:TicketBackupPath) {
        return
    }

    $settings = Get-QOSettings

    # Ensure settings properties exist
    if (-not $settings.TicketStorePath) {
        $defaultDir  = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets'
        $defaultFile = Join-Path $defaultDir 'Tickets.json'
        $settings.TicketStorePath = $defaultFile
    }

    if (-not $settings.LocalTicketBackupPath) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets\Backups'
        $settings.LocalTicketBackupPath = $defaultBackupDir
    }

    Save-QOSettings -Settings $settings

    # Cache
    $script:TicketStorePath  = $settings.TicketStorePath
    $script:TicketBackupPath = $settings.LocalTicketBackupPath

    # Ensure directories
    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    if (-not (Test-Path $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    # Ensure main tickets file
    if (-not (Test-Path $script:TicketStorePath)) {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

# =====================================================================
# DATABASE
# =====================================================================

function New-QODefaultTicketDatabase {
    [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }
}

function Get-QOTickets {

    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultTicketDatabase
        }

        $db = $json | ConvertFrom-Json

        if (-not $db.PSObject.Properties.Name.Contains('SchemaVersion')) {
            $db | Add-Member -NotePropertyName 'SchemaVersion' -NotePropertyValue 1
        }
        if (-not $db.PSObject.Properties.Name.Contains('Tickets')) {
            $db | Add-Member -NotePropertyName 'Tickets' -NotePropertyValue @()
        }

        if ($db.Tickets -isnot [System.Collections.IEnumerable]) {
            $db.Tickets = @($db.Tickets)
        }

        return $db
    }
    catch {
        try {
            if (Test-Path $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmss'))
                Copy-Item $script:TicketStorePath $backupName -ErrorAction SilentlyContinue
            }
        } catch {}

        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath
        return $db
    }
}

function Save-QOTickets {
    param(
        [Parameter(Mandatory)]
        $TicketsDb
    )

    Initialize-QOTicketStorage

    $TicketsDb | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8

    try {
        $stamp      = Get-Date -Format 'yyyyMMddHHmmss'
        $backupName = Join-Path $script:TicketBackupPath ("Tickets_{0}.json" -f $stamp)
        $TicketsDb | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $backupName -Encoding UTF8
    } catch {}
}

# =====================================================================
# TICKET CRUD
# =====================================================================

function New-QOTicket {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Description = '',
        [string]$Category    = 'General',
        [string]$Priority    = 'Normal',
        [string]$Source      = 'Manual',
        [string]$RequesterName  = $null,
        [string]$RequesterEmail = $null,
        [string[]]$Tags         = @()
    )

    $now      = Get-Date
    $ticketId = [guid]::NewGuid().ToString()
    $user     = $env:USERNAME

    $history = @(
        [pscustomobject]@{
            At            = $now
            Action        = 'Created'
            ByUserName    = $user
            ByDisplayName = $user
            FromStatus    = $null
            ToStatus      = 'New'
            Notes         = 'Ticket created'
        }
    )

    [pscustomobject]@{
        Id           = $ticketId
        CreatedAt    = $now
        UpdatedAt    = $now
        Status       = 'New'
        Priority     = $Priority
        Category     = $Category
        Title        = $Title
        Description  = $Description
        Source       = $Source
        RequesterName  = $RequesterName
        RequesterEmail = $RequesterEmail
        Tags         = $Tags
        History      = $history
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)] $Ticket)

    $db = Get-QOTickets

    $tickets = @()
    if ($db.Tickets) {
        $tickets = @($db.Tickets)
    }

    $tickets += $Ticket
    $db.Tickets = $tickets

    Save-QOTickets -TicketsDb $db
    return $Ticket
}

function Get-QOTicketById {
    param([string]$Id)

    $db = Get-QOTickets
    $tickets = $db.Tickets

    $tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

function Set-QOTicketStatus {
    param(
        [string]$Id,
        [string]$Status,
        [string]$Notes = ''
    )

    $db = Get-QOTickets
    $ticket = (Get-QOTicketById -Id $Id)
    if (-not $ticket) { throw "Ticket with Id '$Id' not found." }

    $now = Get-Date

    $oldStatus = $ticket.Status
    $ticket.Status    = $Status
    $ticket.UpdatedAt = $now

    if (-not $ticket.FirstResponseAt -and $Status -ne 'New') {
        $ticket.FirstResponseAt = $now
    }

    if ($Status -eq 'Resolved' -and -not $ticket.ResolvedAt) {
        $ticket.ResolvedAt = $now
    }

    $user = $env:USERNAME

    $ticket.History += [pscustomobject]@{
        At            = $now
        Action        = 'StatusChanged'
        ByUserName    = $user
        ByDisplayName = $user
        FromStatus    = $oldStatus
        ToStatus      = $Status
        Notes         = $Notes
    }

    Save-QOTickets -TicketsDb $db
    return $ticket
}

function Set-QOTicketTitle {
    param(
        [string]$Id,
        [string]$Title
    )

    $db = Get-QOTickets
    $ticket = Get-QOTicketById -Id $Id
    if (-not $ticket) { throw "Ticket with Id '$Id' not found." }

    $ticket.Title     = $Title
    $ticket.UpdatedAt = Get-Date

    Save-QOTickets -TicketsDb $db
    return $ticket
}

# =====================================================================
# EXPORTS
# =====================================================================

Export-ModuleMember -Function `
    Initialize-QOTicketStorage, `
    New-QODefaultTicketDatabase, `
    Get-QOTickets, `
    Save-QOTickets, `
    New-QOTicket, `
    Add-QOTicket, `
    Get-QOTicketById, `
    Set-QOTicketStatus, `
    Set-QOTicketTitle
