# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import Settings
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
# Storage initialisation
# =====================================================================
function Initialize-QOTicketStorage {
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOSettings

    $settings = Ensure-QOSettingProperty $settings "TicketStorePath" ""
    $settings = Ensure-QOSettingProperty $settings "LocalTicketBackupPath" ""
    $settings = Ensure-QOSettingProperty $settings "TicketsColumnLayout" @()

    if ([string]::IsNullOrWhiteSpace($settings.TicketStorePath)) {
        $settings.TicketStorePath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Tickets.json"
    }

    if ([string]::IsNullOrWhiteSpace($settings.LocalTicketBackupPath)) {
        $settings.LocalTicketBackupPath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups"
    }

    Save-QOSettings -Settings $settings

    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    New-Item -ItemType Directory -Path (Split-Path -Parent $script:TicketStorePath) -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null

    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        New-QODefaultTicketDatabase | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
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
        Status    = "Open"
        Priority  = $Priority
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)]$Ticket)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Database $db
    return $Ticket
}

function Remove-QOTicket {
    param([Parameter(Mandatory)][string]$Id)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets | Where-Object { $_.Id -ne $Id })
    Save-QOTickets -Database $db
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

    $subject = ""
    $from    = ""
    $to      = ""
    $body    = ""
    $msgId   = ""
    $received = $null

    try { if ($Email.PSObject.Properties.Name -contains "Subject")   { $subject  = [string]$Email.Subject } } catch { }
    try { if ($Email.PSObject.Properties.Name -contains "From")      { $from     = [string]$Email.From } } catch { }
    try { if ($Email.PSObject.Properties.Name -contains "To")        { $to       = $Email.To } } catch { }
    try { if ($Email.PSObject.Properties.Name -contains "Body")      { $body     = [string]$Email.Body } } catch { }
    try { if ($Email.PSObject.Properties.Name -contains "Snippet")   { if (-not $body) { $body = [string]$Email.Snippet } } } catch { }
    try { if ($Email.PSObject.Properties.Name -contains "MessageId") { $msgId    = [string]$Email.MessageId } } catch { }
    try { if ($Email.PSObject.Properties.Name -contains "Received")  { $received = $Email.Received } } catch { }

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
# Later we will implement actual email reading here.
# =====================================================================
function Sync-QOTicketsFromEmail {
    # Do nothing for now, this is just a safe hook.
    # Next step will be to connect to Outlook/Graph and create tickets.
    return $null
}

Export-ModuleMember -Function `
    Initialize-QOTicketStorage, `
    Get-QOTicketsStorePath, `
    Ensure-QOTicketsStoreDirectory, `
    Get-QOTickets, `
    Save-QOTickets, `
    New-QOTicket, `
    Add-QOTicket, `
    Remove-QOTicket, `
    Get-QOTMonitoredMailboxAddresses, `
    Add-QOTicketFromEmail, `
    Sync-QOTicketsFromEmail
