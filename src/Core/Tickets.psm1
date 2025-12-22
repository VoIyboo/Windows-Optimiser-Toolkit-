# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import Settings (actual path confirmed)
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

function Get-QOTMonitoredMailboxAddresses {
    <#
        Returns the monitored mailbox addresses from Settings.json.
        Always returns an array (can be empty).
    #>

    # Prefer the dedicated Settings function if you added it
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

function Add-QOTicketFromEmail {
    <#
        Creates a ticket from an email payload and persists it to Tickets.json.

        Expected input shape (minimal):
          -Subject (string)
          -From (string)
          -To (string or string[])
          -Received (datetime)
          -Body (string)
          -MessageId (string)  # used to prevent duplicates
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Email
    )

    # Normalise / guard
    $subject   = ([string]($Email.Subject  ?? "")).Trim()
    $from      = ([string]($Email.From     ?? "")).Trim()
    $body      = ([string]($Email.Body     ?? "") )
    $messageId = ([string]($Email.MessageId ?? "")).Trim()

    $to = $Email.To
    if ($to -is [System.Array]) { $to = ($to -join "; ") }
    $to = ([string]($to ?? "")).Trim()

    $received = $Email.Received
    if (-not $received) { $received = Get-Date }

    if (-not $subject) { $subject = "(No subject)" }

    # Load existing tickets safely
    $storePath = Get-QOTicketsStorePath
    Ensure-QOTicketsStoreDirectory | Out-Null

    $tickets = @()
    if (Test-Path -LiteralPath $storePath) {
        try {
            $raw = Get-Content -LiteralPath $storePath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                $tickets = @($parsed)
            }
        } catch {
            $tickets = @()
        }
    }

    # Dedup by MessageId if present
    if ($messageId) {
        foreach ($t in $tickets) {
            try {
                if (($t.Source -eq "Email") -and ($t.EmailMessageId -eq $messageId)) {
                    return $t
                }
            } catch { }
        }
    }

    # Create new ticket object
    $ticket = [pscustomobject]@{
        Id             = ([guid]::NewGuid().ToString())
        Title          = $subject
        Status         = "New"
        Created        = (Get-Date)
        Source         = "Email"

        EmailFrom      = $from
        EmailTo        = $to
        EmailReceived  = $received
        EmailMessageId = $messageId
        EmailBody      = $body
    }

    $tickets = @($tickets) + @($ticket)

    # Persist
    $json = $tickets | ConvertTo-Json -Depth 25
    Set-Content -LiteralPath $storePath -Value $json -Encoding UTF8

    return $ticket
}



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

    if (-not (Test-Path $script:TicketStorePath)) {
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
        $db = Get-Content $script:TicketStorePath -Raw | ConvertFrom-Json
        if (-not $db.Tickets) { $db.Tickets = @() }
        $db.Tickets = @($db.Tickets)
        return $db
    }
    catch {
        New-QODefaultTicketDatabase
    }
}

function Save-QOTickets {
    param([Parameter(Mandatory)]$Database)

    Initialize-QOTicketStorage
    $Database | ConvertTo-Json -Depth 12 |
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
    $db.Tickets += $Ticket
    Save-QOTickets $db
}

function Remove-QOTicket {
    param([Parameter(Mandatory)][string]$Id)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets | Where-Object { $_.Id -ne $Id })
    Save-QOTickets $db
}

Export-ModuleMember -Function `
    Initialize-QOTicketStorage,
    Get-QOTickets,
    Save-QOTickets,
    New-QOTicket,
    Add-QOTicket,
    Remove-QOTicket
    Get-QOTMonitoredMailboxAddresses, `
    Add-QOTicketFromEmai
