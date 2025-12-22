# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import Settings (same folder)
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

# =====================================================================
# Script state
# =====================================================================
$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

# =====================================================================
# Small helpers (PowerShell 5.1 safe)
# =====================================================================
function Get-QOSafeString {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value)
}

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

# =====================================================================
# Read monitored mailboxes from Settings
# =====================================================================
function Get-QOTMonitoredMailboxAddresses {
    <#
        Returns the monitored mailbox addresses from Settings.json.
        Always returns an array (can be empty).
    #>

    # Prefer dedicated Settings function if it exists
    if (Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction SilentlyContinue) {
        $a = @(Get-QOMonitoredMailboxAddresses)
        return @($a | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    }

    # Fallback: read direct from settings object
    $s = Get-QOSettings
    if (-not $s) { return @() }

    $list = @()
    try { $list = @($s.Tickets.EmailIntegration.MonitoredAddresses) } catch { $list = @() }

    return @($list | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
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

    $script:TicketStorePath  = $settings.TicketStorePath
    $script:TicketBackupPath = $settings.LocalTicketBackupPath

    New-Item -ItemType Directory -Path (Split-Path $script:TicketStorePath) -Force | Out-Null
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
        $db = Get-Content -LiteralPath $script:TicketStorePath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $db) { return (New-QODefaultTicketDatabase) }

        if (-not ($db.PSObject.Properties.Name -contains "Tickets") -or $null -eq $db.Tickets) {
            $db | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
        }

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

    if (-not $Database) { throw "Save-QOTickets: Database is null." }

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

        # Optional metadata fields (safe defaults)
        Source         = ""
        EmailFrom      = ""
        EmailTo        = ""
        EmailReceived  = ""
        EmailMessageId = ""
        EmailBody      = ""
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)]$Ticket)

    $db = Get-QOTickets
    $db.Tickets += $Ticket
    Save-QOTickets -Database $db
}

function Remove-QOTicket {
    param([Parameter(Mandatory)][string]$Id)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets | Where-Object { $_.Id -ne $Id })
    Save-QOTickets -Database $db
}

# =====================================================================
# Email -> Ticket
# =====================================================================
function Add-QOTicketFromEmail {
    <#
        Creates a ticket from an email payload and persists it to Tickets.json.

        Expected input shape (minimal):
          - Subject (string)
          - From (string)
          - To (string or string[])
          - Received (datetime or string)
          - Body (string) OR Snippet (string)
          - MessageId (string)  # used to prevent duplicates
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Email
    )

    $subject   = (Get-QOSafeString $Email.Subject).Trim()
    $from      = (Get-QOSafeString $Email.From).Trim()

    $toObj = $null
    if ($Email.PSObject.Properties.Name -contains "To") { $toObj = $Email.To }
    if ($toObj -is [System.Array]) { $toObj = ($toObj -join "; ") }
    $to = (Get-QOSafeString $toObj).Trim()

    $messageId = ""
    if ($Email.PSObject.Properties.Name -contains "MessageId") {
        $messageId = (Get-QOSafeString $Email.MessageId).Trim()
    }

    $received = $null
    if ($Email.PSObject.Properties.Name -contains "Received") { $received = $Email.Received }
    if (-not $received) { $received = Get-Date }

    $body = ""
    if ($Email.PSObject.Properties.Name -contains "Body") {
        $body = (Get-QOSafeString $Email.Body)
    } elseif ($Email.PSObject.Properties.Name -contains "Snippet") {
        $body = (Get-QOSafeString $Email.Snippet)
    }

    if ([string]::IsNullOrWhiteSpace($subject)) { $subject = "(No subject)" }
    if ([string]::IsNullOrWhiteSpace($from))    { $from    = "Unknown sender" }

    $db = Get-QOTickets

    # Dedup by MessageId
    if ($messageId) {
        foreach ($t in @($db.Tickets)) {
            try {
                if (($t.Source -eq "Email") -and ($t.EmailMessageId -eq $messageId)) {
                    return $t
                }
            } catch { }
        }
    }

    $ticket = New-QOTicket -Title $subject -Priority "Normal"

    # Fill email metadata (these properties exist on our ticket template)
    $ticket.Source         = "Email"
    $ticket.EmailFrom      = $from
    $ticket.EmailTo        = $to
    $ticket.EmailReceived  = (Get-QOSafeString $received)
    $ticket.EmailMessageId = $messageId
    $ticket.EmailBody      = $body

    $db.Tickets += $ticket
    Save-QOTickets -Database $db

    return $ticket
}

Export-ModuleMember -Function `
    Initialize-QOTicketStorage, `
    Get-QOTickets, `
    Save-QOTickets, `
    New-QOTicket, `
    Add-QOTicket, `
    Remove-QOTicket, `
    Get-QOTMonitoredMailboxAddresses, `
    Add-QOTicketFromEmail
