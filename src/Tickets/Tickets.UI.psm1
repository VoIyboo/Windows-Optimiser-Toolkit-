# src\Tickets\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Settings.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1")  -Force -ErrorAction Stop


# NOTE:
# Do NOT import "$PSScriptRoot\Settings.psm1" (it does not exist in src\Tickets)
# Do NOT import Tickets.psm1 from inside Tickets.psm1 (recursion).
# This module is self-contained.

# =====================================================================
# SETTINGS ENGINE (LOCAL TO THIS MODULE)
# =====================================================================

# Path for settings.json (shared by toolkit)
$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QOSettings {

    # First run: create defaults
    if (-not (Test-Path -LiteralPath $script:QOSettingsPath)) {

        $default = [PSCustomObject]@{
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }

        $dir = Split-Path -Parent $script:QOSettingsPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $default | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:QOSettingsPath -Encoding UTF8
        return $default
    }

    # Read json safely
    $json = $null
    try {
        $json = Get-Content -LiteralPath $script:QOSettingsPath -Raw -ErrorAction Stop
    }
    catch {
        $json = $null
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return [PSCustomObject]@{
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }
    }

    $settings = $null
    try {
        $settings = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # If settings.json is corrupt, fall back to defaults (do not throw here)
        $settings = [PSCustomObject]@{
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }
    }

    # Ensure properties exist
    if (-not ($settings.PSObject.Properties.Name -contains 'TicketsColumnLayout')) {
        $settings | Add-Member -NotePropertyName TicketsColumnLayout -NotePropertyValue @() -Force
    }
    if (-not ($settings.PSObject.Properties.Name -contains 'TicketStorePath')) {
        $settings | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $null -Force
    }
    if (-not ($settings.PSObject.Properties.Name -contains 'LocalTicketBackupPath')) {
        $settings | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue $null -Force
    }

    # Always keep layout as an array
    if ($settings.TicketsColumnLayout -is [string]) {
        $settings.TicketsColumnLayout = @()
    }
    elseif ($settings.TicketsColumnLayout -isnot [System.Collections.IEnumerable]) {
        $settings.TicketsColumnLayout = @($settings.TicketsColumnLayout)
    }
    else {
        $settings.TicketsColumnLayout = @($settings.TicketsColumnLayout)
    }

    return $settings
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $dir = Split-Path -Parent $script:QOSettingsPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:QOSettingsPath -Encoding UTF8
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

    # Default primary store:
    #   %LOCALAPPDATA%\StudioVoly\QuinnToolkit\Tickets\Tickets.json
    if ([string]::IsNullOrWhiteSpace([string]$settings.TicketStorePath)) {
        $defaultTicketsDir  = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets'
        $defaultTicketsFile = Join-Path $defaultTicketsDir 'Tickets.json'
        $settings.TicketStorePath = $defaultTicketsFile
    }

    # Default backup folder:
    #   %LOCALAPPDATA%\StudioVoly\QuinnToolkit\Tickets\Backups
    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath)) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets\Backups'
        $settings.LocalTicketBackupPath = $defaultBackupDir
    }

    # Persist defaults
    Save-QOSettings -Settings $settings

    # Cache
    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    # Ensure directories
    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    # Ensure main tickets file
    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
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

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        if (-not ($db.PSObject.Properties.Name -contains 'SchemaVersion')) {
            $db | Add-Member -NotePropertyName 'SchemaVersion' -NotePropertyValue 1 -Force
        }
        if (-not ($db.PSObject.Properties.Name -contains 'Tickets')) {
            $db | Add-Member -NotePropertyName 'Tickets' -NotePropertyValue @() -Force
        }

        # Always ensure Tickets is an array
        if ($null -eq $db.Tickets) {
            $db.Tickets = @()
        }
        elseif ($db.Tickets -is [string]) {
            $db.Tickets = @($db.Tickets)
        }
        elseif ($db.Tickets -isnot [System.Collections.IEnumerable]) {
            $db.Tickets = @($db.Tickets)
        }
        else {
            $db.Tickets = @($db.Tickets)
        }

        return $db
    }
    catch {
        # Backup corrupt DB if it exists
        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmss'))
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupName -ErrorAction SilentlyContinue
            }
        } catch {}

        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
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

    # Best effort backup
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
        Id             = $ticketId
        CreatedAt      = $now
        UpdatedAt      = $now
        Status         = 'New'
        Priority       = $Priority
        Category       = $Category
        Title          = $Title
        Description    = $Description
        Source         = $Source
        RequesterName  = $RequesterName
        RequesterEmail = $RequesterEmail
        Tags           = @($Tags)
        History        = @($history)
    }
}

function Add-QOTicket {
    param(
        [Parameter(Mandatory)]
        $Ticket
    )

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + @($Ticket)

    Save-QOTickets -TicketsDb $db
    return $Ticket
}

function Get-QOTicketById {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $db = Get-QOTickets
    @($db.Tickets) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

function Set-QOTicketStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$Status,
        [string]$Notes = ''
    )

    $db = Get-QOTickets
    $ticket = Get-QOTicketById -Id $Id
    if (-not $ticket) { throw "Ticket with Id '$Id' not found." }

    $now = Get-Date
    $oldStatus = [string]$ticket.Status

    $ticket.Status    = $Status
    $ticket.UpdatedAt = $now

    if (-not ($ticket.PSObject.Properties.Name -contains 'FirstResponseAt')) {
        $ticket | Add-Member -NotePropertyName FirstResponseAt -NotePropertyValue $null -Force
    }
    if (-not ($ticket.PSObject.Properties.Name -contains 'ResolvedAt')) {
        $ticket | Add-Member -NotePropertyName ResolvedAt -NotePropertyValue $null -Force
    }

    if (-not $ticket.FirstResponseAt -and $Status -ne 'New') {
        $ticket.FirstResponseAt = $now
    }

    if ($Status -eq 'Resolved' -and -not $ticket.ResolvedAt) {
        $ticket.ResolvedAt = $now
    }

    $user = $env:USERNAME

    $ticket.History = @($ticket.History) + @(
        [pscustomobject]@{
            At            = $now
            Action        = 'StatusChanged'
            ByUserName    = $user
            ByDisplayName = $user
            FromStatus    = $oldStatus
            ToStatus      = $Status
            Notes         = $Notes
        }
    )

    Save-QOTickets -TicketsDb $db
    return $ticket
}

function Set-QOTicketTitle {
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
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

function Remove-QOTicket {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $db = Get-QOTickets
    $tickets = @($db.Tickets)

    $beforeCount = $tickets.Count
    $tickets = @($tickets | Where-Object { $_.Id -ne $Id })

    $db.Tickets = @($tickets)
    Save-QOTickets -TicketsDb $db

    return ($beforeCount -ne $tickets.Count)
}

# =====================================================================
# EXPORTS
# =====================================================================

Export-ModuleMember -Function `
    Get-QOSettings, `
    Save-QOSettings, `
    Initialize-QOTicketStorage, `
    New-QODefaultTicketDatabase, `
    Get-QOTickets, `
    Save-QOTickets, `
    New-QOTicket, `
    Add-QOTicket, `
    Get-QOTicketById, `
    Set-QOTicketStatus, `
    Set-QOTicketTitle, `
    Remove-QOTicket
