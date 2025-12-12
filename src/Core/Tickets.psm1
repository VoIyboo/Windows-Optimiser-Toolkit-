# Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System

# Uses global Settings.psm1 for paths and persistence
Import-Module "$PSScriptRoot\Settings.psm1" -Force

# Script-level cache of resolved paths
$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

function New-QODefaultTicketDatabase {
    <#
        Creates a blank ticket database object.

        {
          "SchemaVersion": 1,
          "Tickets": []
        }
    #>
    return [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }
}

function Initialize-QOTicketStorage {
    <#
        Resolves and ensures ticket store and backup paths exist.
        Uses Get-QOSettings / Save-QOSettings from Settings.psm1.
    #>

    # If we already resolved paths, stop
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOSettings

    # Default primary store:
    # %LOCALAPPDATA%\StudioVoly\QuinnToolkit\Tickets\Tickets.json
    if ([string]::IsNullOrWhiteSpace($settings.TicketStorePath)) {
        $defaultTicketsDir  = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets'
        $defaultTicketsFile = Join-Path $defaultTicketsDir 'Tickets.json'

        # Use Add-Member -Force so this works even if the property is missing
        $settings | Add-Member -NotePropertyName 'TicketStorePath' -NotePropertyValue $defaultTicketsFile -Force
    }

    # Default backup folder:
    # %LOCALAPPDATA%\StudioVoly\QuinnToolkit\Tickets\Backups
    if ([string]::IsNullOrWhiteSpace($settings.LocalTicketBackupPath)) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets\Backups'
        $settings | Add-Member -NotePropertyName 'LocalTicketBackupPath' -NotePropertyValue $defaultBackupDir -Force
    }

    # Persist any new defaults back to settings.json
    Save-QOSettings -Settings $settings

    # Cache resolved paths
    $script:TicketStorePath  = $settings.TicketStorePath
    $script:TicketBackupPath = $settings.LocalTicketBackupPath

    # Ensure primary folder exists
    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    # Ensure backup folder exists
    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    # Ensure the main tickets file exists
    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

function Get-QOTickets {
    <#
        Returns the current ticket database object.
        If the file is missing or corrupted, it self-heals with a default DB.
    #>

    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return (New-QODefaultTicketDatabase)
        }

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        # Self-heal schema
        if (-not ($db.PSObject.Properties.Name -contains 'SchemaVersion')) {
            $db | Add-Member -NotePropertyName 'SchemaVersion' -NotePropertyValue 1 -Force
        }
        if (-not ($db.PSObject.Properties.Name -contains 'Tickets')) {
            $db | Add-Member -NotePropertyName 'Tickets' -NotePropertyValue @() -Force
        }

        # Always normalise tickets to an array
        if ($null -eq $db.Tickets) {
            $db.Tickets = @()
        }
        else {
            $db.Tickets = @($db.Tickets)
        }

        return $db
    }
    catch {
        # Backup broken file (best effort)
        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmss'))
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupName -ErrorAction SilentlyContinue
            }
        } catch { }

        # Recreate
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
        return $db
    }
}

function Save-QOTickets {
    <#
        Saves the provided ticket database to the primary path
        and writes a timestamped backup copy.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $TicketsDb
    )

    Initialize-QOTicketStorage

    # Primary save
    $TicketsDb | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8

    # Backup save (best effort)
    try {
        $stamp      = Get-Date -Format 'yyyyMMddHHmmss'
        $backupName = Join-Path $script:TicketBackupPath ("Tickets_{0}.json" -f $stamp)
        $TicketsDb | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupName -Encoding UTF8
    } catch { }
}

function New-QOTicket {
    <#
        Creates a new ticket object in memory only.
        Use Add-QOTicket to persist it.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [string]$Description      = '',
        [string]$Category         = 'General',
        [string]$Priority         = 'Normal',
        [string]$Source           = 'Manual',
        [string]$SourceEmailId    = $null,
        [string]$RequesterName    = $null,
        [string]$RequesterEmail   = $null,
        [string[]]$Tags           = @()
    )

    $now         = Get-Date
    $ticketId    = [guid]::NewGuid().ToString()
    $userName    = $env:USERNAME
    $displayName = $env:USERNAME

    $history = @(
        [pscustomobject]@{
            At            = $now
            Action        = 'Created'
            ByUserName    = $userName
            ByDisplayName = $displayName
            FromStatus    = $null
            ToStatus      = 'New'
            Notes         = 'Ticket created'
        }
    )

    return [pscustomobject]@{
        Id                     = $ticketId
        CreatedAt              = $now
        UpdatedAt              = $now
        Status                 = 'New'
        Priority               = $Priority
        Category               = $Category
        Title                  = $Title
        Description            = $Description
        Source                 = $Source
        SourceEmailId          = $SourceEmailId
        RequesterName          = $RequesterName
        RequesterEmail         = $RequesterEmail
        AssignedToUserName     = $null
        AssignedToDisplayName  = $null
        AssignedAt             = $null
        FirstResponseAt        = $null
        ResolvedAt             = $null
        Tags                   = $Tags
        History                = $history
    }
}

function Add-QOTicket {
    <#
        Adds a ticket object to the database and saves it.
        Returns the same ticket object.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Ticket
    )

    $db = Get-QOTickets

    $tickets = @($db.Tickets)
    $tickets += $Ticket
    $db.Tickets = $tickets

    Save-QOTickets -TicketsDb $db
    return $Ticket
}

function Get-QOTicketById {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $db = Get-QOTickets
    return ($db.Tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Set-QOTicketStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Notes = ''
    )

    $db = Get-QOTickets
    $ticket = $db.Tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $ticket) { throw "Ticket with Id '$Id' not found." }

    $now       = Get-Date
    $oldStatus = $ticket.Status

    $ticket.Status    = $Status
    $ticket.UpdatedAt = $now

    if (-not $ticket.FirstResponseAt -and $Status -ne 'New') {
        $ticket.FirstResponseAt = $now
    }

    if ($Status -eq 'Resolved' -and -not $ticket.ResolvedAt) {
        $ticket.ResolvedAt = $now
    }

    $userName    = $env:USERNAME
    $displayName = $env:USERNAME

    $historyEntry = [pscustomobject]@{
        At            = $now
        Action        = 'StatusChanged'
        ByUserName    = $userName
        ByDisplayName = $displayName
        FromStatus    = $oldStatus
        ToStatus      = $Status
        Notes         = $Notes
    }

    $ticket.History = @($ticket.History) + $historyEntry

    Save-QOTickets -TicketsDb $db
    return $ticket
}

function Set-QOTicketTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $db = Get-QOTickets
    $ticket = $db.Tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $ticket) { throw "Ticket with Id '$Id' not found." }

    $ticket.Title     = $Title
    $ticket.UpdatedAt = Get-Date

    Save-QOTickets -TicketsDb $db
    return $ticket
}

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
