# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import Settings
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

# Import Outlook ticket sync (optional)
try {
    $outlookMod = Join-Path $PSScriptRoot "..\Tickets\Tickets.Email.Outlook.psm1"
    if (Test-Path -LiteralPath $outlookMod) {
        Import-Module $outlookMod -Force -ErrorAction Stop
    }
} catch {
    # Outlook integration is optional
}


# =====================================================================
# Script state
# =====================================================================
$script:TicketStorePath  = $null
$script:TicketBackupPath = $null
$script:ValidTicketStatuses = @(
    "New",
    "In Progress",
    "Waiting on User",
    "No Longer Required",
    "Completed"
)

# =====================================================================
# Helpers
# =====================================================================
function Ensure-QOSettingProperty {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$DefaultValue
    )

    if (-not $Settings) { throw "Settings object is null." }

    if ($Settings.PSObject.Properties.Name -notcontains $Name) {
        $Settings | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue -Force
    }

    return $Settings
}

function New-QODefaultTicketDatabase {
    [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }
}

function New-QODefaultTicketsFile {
    param([Parameter(Mandatory)][string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-QODefaultTicketDatabase | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

function Test-QOIsBadTicketPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    $p = [string]$Path

    # Anything inside TEMP extraction paths is not stable
    if ($p -like "*\AppData\Local\Temp\QuinnOptimiserToolkit\*") { return $true }
    if ($p -like "*\Temp\QuinnOptimiserToolkit\*") { return $true }

    # If it's not a JSON file, treat as bad
    if ($p -notlike "*.json") { return $true }

    return $false
}

function Get-QOTicketsStorePath {
    Initialize-QOTicketStorage
    return $script:TicketStorePath
}

function Ensure-QOTicketsStoreDirectory {
    Initialize-QOTicketStorage
    $dir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

# =====================================================================
# Storage initialisation (with path migration)
# =====================================================================
function Initialize-QOTicketStorage {
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOSettings

    $settings = Ensure-QOSettingProperty $settings "TicketStorePath" ""
    $settings = Ensure-QOSettingProperty $settings "LocalTicketBackupPath" ""
    $settings = Ensure-QOSettingProperty $settings "TicketsColumnLayout" @()

    $stableStorePath  = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Tickets.json"
    $stableBackupPath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups"

    $currentPath = [string]$settings.TicketStorePath
    $needReset   = $false

    # Decide if current path is unsafe or unusable
    if (Test-QOIsBadTicketPath -Path $currentPath) {
        $needReset = $true
    } elseif (-not (Test-Path -LiteralPath $currentPath)) {
        # Missing file, prefer stable path (we will attempt migrate if possible)
        $needReset = $true
    }

    # Attempt migration if we are changing paths AND old file exists somewhere
    if ($needReset) {
        # If old path exists and stable doesn't, copy it across
        try {
            if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
                if (Test-Path -LiteralPath $currentPath) {
                    $stableDir = Split-Path -Parent $stableStorePath
                    if (-not (Test-Path -LiteralPath $stableDir)) {
                        New-Item -ItemType Directory -Path $stableDir -Force | Out-Null
                    }

                    if (-not (Test-Path -LiteralPath $stableStorePath)) {
                        Copy-Item -LiteralPath $currentPath -Destination $stableStorePath -Force
                    }
                }
            }
        } catch { }

        $settings.TicketStorePath = $stableStorePath
    }

    # Backup path should always be stable
    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath) -or
        ([string]$settings.LocalTicketBackupPath -like "*\AppData\Local\Temp\QuinnOptimiserToolkit\*")) {
        $settings.LocalTicketBackupPath = $stableBackupPath
    }

    Save-QOSettings -Settings $settings

    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    # Ensure directories exist
    New-Item -ItemType Directory -Path (Split-Path -Parent $script:TicketStorePath) -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null

    # Ensure the tickets file exists
    New-QODefaultTicketsFile -Path $script:TicketStorePath
}

# =====================================================================
# Database IO
# =====================================================================
function Get-QOTickets {
    Initialize-QOTicketStorage

    try {
        $db = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $db) { return (New-QODefaultTicketDatabase) }

        if (-not ($db.PSObject.Properties.Name -contains "Tickets")) {
            $db | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
        }

        if ($null -eq $db.Tickets) { $db.Tickets = @() }
        $db.Tickets = @($db.Tickets)
        foreach ($ticket in $db.Tickets) {
            if ($null -eq $ticket) { continue }

            if (-not ($ticket.PSObject.Properties.Name -contains "DeletedAt")) {
                $ticket | Add-Member -NotePropertyName DeletedAt -NotePropertyValue $null -Force
            }

            if (-not ($ticket.PSObject.Properties.Name -contains "Folder")) {
                $folderValue = if ($ticket.DeletedAt) { "Deleted" } else { "Active" }
                $ticket | Add-Member -NotePropertyName Folder -NotePropertyValue $folderValue -Force
            } elseif ($ticket.DeletedAt -and $ticket.Folder -ne "Deleted") {
                $ticket.Folder = "Deleted"
            } elseif (-not $ticket.DeletedAt -and $ticket.Folder -eq "Deleted") {
                $ticket.DeletedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }



            if (-not ($ticket.PSObject.Properties.Name -contains "Status")) {
                $ticket | Add-Member -NotePropertyName Status -NotePropertyValue "New" -Force
            }

            if ([string]::IsNullOrWhiteSpace([string]$ticket.Status)) {
                $ticket.Status = "New"
            }

            if ($ticket.Status -eq "Open") {
                $ticket.Status = "In Progress"
            }

            if ($script:ValidTicketStatuses -notcontains $ticket.Status) {
                $ticket.Status = "New"
            }
        }

        return $db
    }
    catch {
        return (New-QODefaultTicketDatabase)
    }
}

function Save-QOTickets {
    param([Parameter(Mandatory)]$Database)

    Initialize-QOTicketStorage

    if (-not ($Database.PSObject.Properties.Name -contains "Tickets")) {
        $Database | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
    }

    $Database | ConvertTo-Json -Depth 25 |
        Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
}

# =====================================================================
# CRUD
# =====================================================================
function New-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Priority = "Normal"
    )

    $now = Get-Date

    [pscustomobject]@{
        Id        = [guid]::NewGuid().ToString()
        Title     = $Title
        CreatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
        Status    = "New"
        Priority  = $Priority
        Folder    = "Active"
        DeletedAt = $null
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)]$Ticket)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Database $db
    return $Ticket
}

function Update-QOTicket {
    param([Parameter(Mandatory)]$Ticket)

    $db = Get-QOTickets

    $ticketId = $null
    try { $ticketId = [string]$Ticket.Id } catch { }
    if ([string]::IsNullOrWhiteSpace($ticketId)) {
        return $false
    }

    $updated = $false
    foreach ($existing in @($db.Tickets)) {
        if ($null -eq $existing) { continue }
        if ($existing.Id -ne $ticketId) { continue }

        foreach ($prop in $Ticket.PSObject.Properties) {
            if ($prop.Name -eq "Id") { continue }
            $existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }

        $updated = $true
        break
    }

    if ($updated) {
        Save-QOTickets -Database $db
    }

    return $updated
}



function Remove-QOTicket {
    param([Parameter(Mandatory)][string[]]$Id)

    $db = Get-QOTickets
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Folder = "Deleted"
            $ticket.DeletedAt = $now
        }
    }
    Save-QOTickets -Database $db
}

function Restore-QOTickets {
    param([Parameter(Mandatory)][string[]]$Id)

    $db = Get-QOTickets
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Folder = "Active"
            $ticket.DeletedAt = $null
        }
    }

    Save-QOTickets -Database $db
}

function Set-QOTicketsStatus {
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [Parameter(Mandatory)][string]$Status
    )

    $statusValue = [string]$Status
    if ($statusValue -eq "Open") { $statusValue = "In Progress" }

    if ($script:ValidTicketStatuses -notcontains $statusValue) {
        throw "Invalid status '$Status'. Allowed: $($script:ValidTicketStatuses -join ', ')."
    }

    $db = Get-QOTickets
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Status = $statusValue
        }
    }

    Save-QOTickets -Database $db
}

function Get-QOTicketStatuses {
    return @($script:ValidTicketStatuses)
}

function Get-QOTicketsFiltered {
    param(
        [string[]]$Status,
        [bool]$IncludeDeleted
    )

    $db = Get-QOTickets
    $statuses = @(
        $Status |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
    )

    if ($statuses.Count -eq 0) {
        if (-not $PSBoundParameters.ContainsKey("Status")) {
            $statuses = @($script:ValidTicketStatuses)
        } else {
            return @()
        }
    }

    $includeDeleted = [bool]$IncludeDeleted

    return @(
        $db.Tickets |
            Where-Object { $_ } |
            Where-Object { $statuses -contains $_.Status } |
            Where-Object { $includeDeleted -or ($_.Folder -ne "Deleted") }
    )
}

# =====================================================================
# Settings bridge for monitored addresses
# =====================================================================
function Get-QOTMonitoredMailboxAddresses {
    # Prefer dedicated Settings function if available
    if (Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction SilentlyContinue) {
        $a = @(Get-QOMonitoredMailboxAddresses)
        return @(
            $a |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
        )
    }

    # Fallback (should not really happen now)
    $s = Get-QOSettings
    if (-not $s) { return @() }

    try {
        $list = @($s.Tickets.EmailIntegration.MonitoredAddresses)
        return @(
            $list |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
        )
    } catch {
        return @()
    }
}

# =====================================================================
# Email ticket creation (PowerShell 5.1 safe)
# =====================================================================
function Add-QOTicketFromEmail {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Email
    )

    $subject  = ""
    $from     = ""
    $to       = ""
    $body     = ""
    $msgId    = ""
    $received = $null

    try {
        if ($Email.PSObject.Properties.Name -contains "Subject") {
            $subject = [string]$Email.Subject
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "From") {
            $from = [string]$Email.From
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "To") {
            $to = $Email.To
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Body") {
            $body = [string]$Email.Body
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Snippet") {
            if (-not $body) {
                $body = [string]$Email.Snippet
            }
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "MessageId") {
            $msgId = [string]$Email.MessageId
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Received") {
            $received = $Email.Received
        }
    } catch { }

    $subject = ($subject + "").Trim()
    $from    = ($from + "").Trim()
    $msgId   = ($msgId + "").Trim()

    if ($to -is [System.Array]) { $to = ($to -join "; ") }
    $to = ([string]($to + "")).Trim()

    if (-not $received) { $received = Get-Date }
    if ([string]::IsNullOrWhiteSpace($subject)) { $subject = "(No subject)" }
    if ([string]::IsNullOrWhiteSpace($from))    { $from = "Unknown sender" }

    $db = Get-QOTickets

    # Dedup by MessageId
    if ($msgId) {
        foreach ($t in @($db.Tickets)) {
            try {
                if (($t.Source -eq "Email") -and ($t.EmailMessageId -eq $msgId)) {
                    return $t
                }
            } catch { }
        }
    }

    $ticket = [pscustomobject]@{
        Id             = ([guid]::NewGuid().ToString())
        Title          = $subject
        Status         = "New"
        CreatedAt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Priority       = "Normal"
        Source         = "Email"
        Folder         = "Active"
        DeletedAt      = $null
        EmailFrom      = $from
        EmailTo        = $to
        EmailReceived  = $received
        EmailMessageId = $msgId
        EmailBody      = $body
    }

    $db.Tickets = @($db.Tickets) + @($ticket)
    Save-QOTickets -Database $db

    return $ticket
}

# =====================================================================
# Sync stub (so UI can call it without exploding)
# =====================================================================
function Sync-QOTicketsFromEmail {
    param(
        [int]$MaxPerMailbox = 50,
        [switch]$MarkAsRead
    )

    try {
        if (-not (Get-Command Sync-QOTicketsFromOutlook -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{ Added = 0; Note = "Outlook sync function not loaded." }
        }

        $r = Sync-QOTicketsFromOutlook -MaxPerMailbox $MaxPerMailbox -MarkAsRead:$MarkAsRead
        if (-not $r) { $r = [pscustomobject]@{ Added = 0; Note = "Outlook sync returned nothing." } }

        return $r
    }
    catch {
        return [pscustomobject]@{
            Added = 0
            Note  = ("Sync failed: " + $_.Exception.Message)
        }
    }
}


$exports = @(
    "Initialize-QOTicketStorage",
    "Get-QOTicketsStorePath",
    "Ensure-QOTicketsStoreDirectory",
    "Get-QOTickets",
    "Save-QOTickets",
    "New-QOTicket",
    "Add-QOTicket",
    "Update-QOTicket",
    "Remove-QOTicket",
    "Restore-QOTickets",
    "Set-QOTicketsStatus",
    "Get-QOTicketStatuses",
    "Get-QOTicketsFiltered",
    "Get-QOTMonitoredMailboxAddresses",
    "Add-QOTicketFromEmail",
    "Sync-QOTicketsFromEmail"
)

# Only export Outlook sync if it actually exists (module loaded)
if (Get-Command Sync-QOTicketsFromOutlook -ErrorAction SilentlyContinue) {
    $exports += "Sync-QOTicketsFromOutlook"
}

Export-ModuleMember -Function $exports
