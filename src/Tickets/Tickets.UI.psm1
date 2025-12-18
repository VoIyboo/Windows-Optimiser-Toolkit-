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

    # If the property exists but is null/empty and we want a default, caller can set afterwards
    return $Settings
}

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

# =====================================================================
# Storage initialisation
# =====================================================================

function Initialize-QOTicketStorage {
    <#
        Resolves and ensures ticket store and backup paths exist.
        Uses Get-QOSettings / Save-QOSettings from Settings.psm1.
    #>

    if ($script:TicketStorePath -and $script:TicketBackupPath) {
        return
    }

    $settings = Get-QOSettings

    # Ensure settings has the properties we rely on
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketStorePath"       -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "LocalTicketBackupPath" -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketsColumnLayout"   -DefaultValue @()

    # Default primary store
    if ([string]::IsNullOrWhiteSpace([string]$settings.TicketStorePath)) {
        $defaultTicketsDir  = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
        $defaultTicketsFile = Join-Path $defaultTicketsDir "Tickets.json"
        $settings.TicketStorePath = $defaultTicketsFile
    }

    # Default backup folder
    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath)) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups"
        $settings.LocalTicketBackupPath = $defaultBackupDir
    }

    # Persist any new defaults back to settings.json
    Save-QOSettings -Settings $settings

    # Cache resolved paths
    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    if ([string]::IsNullOrWhiteSpace($script:TicketStorePath)) {
        throw "TicketStorePath resolved to null/empty. Settings may be corrupted."
    }

    # Ensure directories exist
    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    # Ensure the main tickets file exists
    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

# =====================================================================
# Database IO
# =====================================================================

function Get-QOTickets {
    <#
        Returns the current ticket database object.
        If the file is missing or corrupted, it self heals with a default DB.
    #>

    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultTicketDatabase
        }

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        # Light schema self heal
        if (-not $db.PSObject.Properties.Name.Contains("SchemaVersion")) {
            $db | Add-Member -NotePropertyName "SchemaVersion" -NotePropertyValue 1
        }
        if (-not $db.PSObject.Properties.Name.Contains("Tickets")) {
            $db | Add-Member -NotePropertyName "Tickets" -NotePropertyValue @()
        }

        # Normalise Tickets to array
        if ($null -eq $db.Tickets) {
            $db.Tickets = @()
        }
        else {
            $db.Tickets = @($db.Tickets)
        }

        return $db
    }
    catch {
        # Backup the broken file, then recreate
        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format "yyyyMMddHHmmss"))
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupName -ErrorAction SilentlyContinue
            }
        }
        catch { }

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
        [Parameter(Mandatory)]
        $TicketsDb
    )

    Initialize-QOTicketStorage

    # Primary save
    $TicketsDb | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8

    # Backup save (best effort)
    try {
        $stamp      = Get-Date -Format "yyyyMMddHHmmss"
        $backupName = Join-Path $script:TicketBackupPath ("Tickets_{0}.json" -f $stamp)
        $TicketsDb | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupName -Encoding UTF8
    }
    catch {
        # Intentionally ignore backup errors
    }
}

# =====================================================================
# Ticket CRUD
# =====================================================================

function New-QOTicket {
    <#
        Creates a new ticket object in memory only.
        Use Add-QOTicket to persist it to Tickets.json.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Description    = "",
        [string]$Category       = "General",
        [string]$Priority       = "Normal",  # Low | Normal | High | Urgent
        [string]$Source         = "Manual",  # Manual | Email | Script
        [string]$SourceEmailId  = $null,
        [string]$RequesterName  = $null,
        [string]$RequesterEmail = $null,
        [string[]]$Tags         = @()
    )

    $now      = Get-Date
    $ticketId = [guid]::NewGuid().ToString()

    $userName    = $env:USERNAME
    $displayName = $env:USERNAME

    $history = @(
        [pscustomobject]@{
            At            = $now
            Action        = "Created"
            ByUserName    = $userName
            ByDisplayName = $displayName
            FromStatus    = $null
            ToStatus      = "New"
            Notes         = "Ticket created"
        }
    )

    return [pscustomobject]@{
        Id                    = $ticketId
        CreatedAt             = $now
        UpdatedAt             = $now
        Status                = "New"
        Priority              = $Priority
        Category              = $Category
        Title                 = $Title
        Description           = $Description
        Source                = $Source
        SourceEmailId         = $SourceEmailId
        RequesterName         = $RequesterName
        RequesterEmail        = $RequesterEmail
        AssignedToUserName    = $null
        AssignedToDisplayName = $null
        AssignedAt            = $null
        FirstResponseAt       = $null
        ResolvedAt            = $null
        Tags                  = $Tags
        History               = $history
    }
}

function Add-QOTicket {
    <#
        Adds a ticket object to the database and saves it.
        Returns the same ticket object.
    #>
    param(
        [Parameter(Mandatory)]
        $Ticket
    )

    $db      = Get-QOTickets
    $tickets = @($db.Tickets)
    $tickets += $Ticket
    $db.Tickets = $tickets

    Save-QOTickets -TicketsDb $db
    return $Ticket
}

function Get-QOTicketById {
    <#
        Fetch a single ticket by its Id.
        Returns $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $db      = Get-QOTickets
    $tickets = @($db.Tickets)

    return ($tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Remove-QOTicket {
    <#
        Removes a ticket by Id and saves the database.
        Returns $true if removed, $false if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $db      = Get-QOTickets
    $tickets = @($db.Tickets)

    $before = $tickets.Count
    $tickets = @($tickets | Where-Object { $_.Id -ne $Id })

    if ($tickets.Count -eq $before) {
        return $false
    }

    $db.Tickets = $tickets
    Save-QOTickets -TicketsDb $db
    return $true
}

function Set-QOTicketStatus {
    <#
        Updates a ticket's Status and history, then saves the database.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Status,

        [string]$Notes = ""
    )

    $db      = Get-QOTickets
    $tickets = @($db.Tickets)

    $ticket = $tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $ticket) {
        throw "Ticket with Id '$Id' not found."
    }

    $now       = Get-Date
    $oldStatus = [string]$ticket.Status

    $ticket.Status    = $Status
    $ticket.UpdatedAt = $now

    if (-not $ticket.FirstResponseAt -and $Status -ne "New") {
        $ticket.FirstResponseAt = $now
    }

    if ($Status -eq "Resolved" -and -not $ticket.ResolvedAt) {
        $ticket.ResolvedAt = $now
    }

    $userName    = $env:USERNAME
    $displayName = $env:USERNAME

    $historyEntry = [pscustomobject]@{
        At            = $now
        Action        = "StatusChanged"
        ByUserName    = $userName
        ByDisplayName = $displayName
        FromStatus    = $oldStatus
        ToStatus      = $Status
        Notes         = $Notes
    }

    $ticket.History = @($ticket.History) + $historyEntry

    $db.Tickets = $tickets
    Save-QOTickets -TicketsDb $db

    return $ticket
}

function Set-QOTicketTitle {
    <#
        Updates a ticket title and saves the database.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Title
    )

    $db      = Get-QOTickets
    $tickets = @($db.Tickets)

    $ticket = $tickets | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $ticket) {
        throw "Ticket with Id '$Id' not found."
    }

    $ticket.Title     = $Title
    $ticket.UpdatedAt = Get-Date

    $db.Tickets = $tickets
    Save-QOTickets -TicketsDb $db

    return $ticket
}

# =====================================================================
# Exports
# =====================================================================

Export-ModuleMember -Function `
    Initialize-QOTicketStorage, `
    New-QODefaultTicketDatabase, `
    Get-QOTickets, `
    Save-QOTickets, `
    New-QOTicket, `
    Add-QOTicket, `
    Get-QOTicketById, `
    Remove-QOTicket, `
    Set-QOTicketStatus, `
    Set-QOTicketTitle
