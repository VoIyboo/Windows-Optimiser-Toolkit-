# Tickets.psm1
# Storage + email ingestion for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Import shared settings
Import-Module "$PSScriptRoot\Settings.psm1" -Force

# =====================================================================
# STORAGE PATHS
# =====================================================================

$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

function Initialize-QOTicketStorage {

    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $s = Get-QOSettings

    if ([string]::IsNullOrWhiteSpace($s.TicketStorePath)) {
        $dir  = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
        $file = Join-Path $dir "Tickets.json"
        $s.TicketStorePath = $file
    }

    if ([string]::IsNullOrWhiteSpace($s.LocalTicketBackupPath)) {
        $s.LocalTicketBackupPath = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups"
    }

    Save-QOSettings -Settings $s

    $script:TicketStorePath  = $s.TicketStorePath
    $script:TicketBackupPath = $s.LocalTicketBackupPath

    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    if (-not (Test-Path $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    if (-not (Test-Path $script:TicketStorePath)) {
        New-QODefaultTicketDatabase |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
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
        $json = Get-Content $script:TicketStorePath -Raw
        $db   = $json | ConvertFrom-Json
        if (-not $db.Tickets) { $db.Tickets = @() }
        return $db
    }
    catch {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 6 | Set-Content $script:TicketStorePath
        return $db
    }
}

function Save-QOTickets {
    param([Parameter(Mandatory)] $TicketsDb)

    Initialize-QOTicketStorage

    $TicketsDb | ConvertTo-Json -Depth 6 | Set-Content $script:TicketStorePath

    try {
        $stamp = Get-Date -Format "yyyyMMddHHmmss"
        $backup = Join-Path $script:TicketBackupPath "Tickets_$stamp.json"
        $TicketsDb | ConvertTo-Json -Depth 6 | Set-Content $backup
    } catch {}
}

# =====================================================================
# TICKET MODEL + CRUD
# =====================================================================

function New-QOTicket {
    param(
        [string]$Title,
        [string]$Description = "",
        [string]$Category = "General",
        [string]$Priority = "Normal",
        [string]$Source = "Manual",
        [string]$RequesterEmail = $null,
        [string[]]$Tags = @()
    )

    $now = Get-Date
    [pscustomobject]@{
        Id             = [guid]::NewGuid().ToString()
        CreatedAt      = $now
        UpdatedAt      = $now
        Status         = "New"
        Priority       = $Priority
        Category       = $Category
        Title          = $Title
        Description    = $Description
        Source         = $Source
        RequesterEmail = $RequesterEmail
        Tags           = $Tags
        History        = @(
            [pscustomobject]@{
                At     = $now
                Action = "Created"
            }
        )
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)] $Ticket)

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + $Ticket
    Save-QOTickets -TicketsDb $db
    return $Ticket
}

# =====================================================================
# EMAIL → TICKET POLLER (OUTLOOK)
# =====================================================================

function Invoke-QOEmailTicketPoll {

    $s = Get-QOSettings
    if (-not $s.Tickets.EmailIntegration.Enabled) { return @() }

    if (-not $s.Tickets.EmailIntegration.MonitoredAddresses) { return @() }

    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastProcessedByMailbox")) {
        $s.Tickets.EmailIntegration |
            Add-Member -NotePropertyName LastProcessedByMailbox -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $created = @()

    $outlook = New-Object -ComObject Outlook.Application
    $ns = $outlook.GetNamespace("MAPI")

    foreach ($mb in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {

        $key = $mb.Trim().ToLower()

        $since = $null
        try {
            $raw = $s.Tickets.EmailIntegration.LastProcessedByMailbox.$key
            if ($raw) { $since = [datetime]::Parse($raw) }
        } catch {}

        if (-not $since) { $since = (Get-Date).AddDays(-3) }

        try {
            $r = $ns.CreateRecipient($mb)
            $r.Resolve()
            if (-not $r.Resolved) { continue }
            $inbox = $ns.GetSharedDefaultFolder($r, 6)
        }
        catch { continue }

        foreach ($mail in @($inbox.Items)) {

            if (-not $mail.ReceivedTime) { continue }
            if ($mail.ReceivedTime -le $since) { continue }

            $ticket = New-QOTicket `
                -Title $mail.Subject `
                -Description $mail.Body `
                -Category "Email" `
                -Priority "Normal" `
                -Source "Email" `
                -RequesterEmail $mail.SenderEmailAddress `
                -Tags @("Email",$key)

            $ticket.CreatedAt = $mail.ReceivedTime
            $ticket.UpdatedAt = $mail.ReceivedTime

            Add-QOTicket -Ticket $ticket | Out-Null
            $created += $ticket

            $s.Tickets.EmailIntegration.LastProcessedByMailbox |
                Add-Member -NotePropertyName $key -NotePropertyValue ($mail.ReceivedTime.ToString("o")) -Force
        }
    }

    Save-QOSettings -Settings $s
    return $created
}

# =====================================================================
# EXPORTS
# =====================================================================

Export-ModuleMember -Function `
    Initialize-QOTicketStorage, `
    Get-QOTickets, `
    Save-QOTickets, `
    New-QOTicket, `
    Add-QOTicket, `
    Invoke-QOEmailTicketPoll
