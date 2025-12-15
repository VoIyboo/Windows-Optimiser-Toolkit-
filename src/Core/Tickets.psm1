# Tickets.psm1
# Storage + email ingestion for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Import shared settings (single source of truth)
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

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
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        New-QODefaultTicketDatabase |
            ConvertTo-Json -Depth 8 |
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
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) { return (New-QODefaultTicketDatabase) }

        $db = $json | ConvertFrom-Json

        if (-not ($db.PSObject.Properties.Name -contains "SchemaVersion")) {
            $db | Add-Member -NotePropertyName SchemaVersion -NotePropertyValue 1 -Force
        }
        if (-not ($db.PSObject.Properties.Name -contains "Tickets")) {
            $db | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
        }

        # Normalise to array
        $db.Tickets = @($db.Tickets)

        return $db
    }
    catch {
        # If corrupted, back it up then reset
        try {
            $stamp = Get-Date -Format "yyyyMMddHHmmss"
            $bad   = Join-Path $script:TicketBackupPath "Tickets_corrupt_$stamp.json"
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $bad -Force -ErrorAction SilentlyContinue
            }
        } catch {}

        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
        return $db
    }
}

function Save-QOTickets {
    param([Parameter(Mandatory)] $TicketsDb)

    Initialize-QOTicketStorage

    $TicketsDb | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8

    try {
        $stamp  = Get-Date -Format "yyyyMMddHHmmss"
        $backup = Join-Path $script:TicketBackupPath "Tickets_$stamp.json"
        $TicketsDb | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backup -Encoding UTF8
    } catch {}
}

# =====================================================================
# TICKET MODEL + CRUD
# =====================================================================

function New-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Description = "",
        [string]$Category = "General",
        [string]$Priority = "Normal",
        [string]$Source = "Manual",
        [string]$RequesterName = $null,
        [string]$RequesterEmail = $null,
        [string[]]$Tags = @()
    )

    $now  = Get-Date
    $user = $env:USERNAME

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
        RequesterName  = $RequesterName
        RequesterEmail = $RequesterEmail
        Tags           = $Tags
        History        = @(
            [pscustomobject]@{
                At            = $now
                Action        = "Created"
                ByUserName    = $user
                ByDisplayName = $user
                Notes         = "Ticket created"
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

function Remove-QOTicket {
    param([Parameter(Mandatory)][string]$Id)

    $db = Get-QOTickets
    $before = @($db.Tickets).Count

    $db.Tickets = @($db.Tickets | Where-Object { "$($_.Id)" -ne "$Id" })

    Save-QOTickets -TicketsDb $db
    return (@($db.Tickets).Count -ne $before)
}

function Get-QOTicketById {
    param([Parameter(Mandatory)][string]$Id)

    $db = Get-QOTickets
    @($db.Tickets) | Where-Object { "$($_.Id)" -eq "$Id" } | Select-Object -First 1
}

# =====================================================================
# EMAIL -> TICKET POLLER (OUTLOOK COM)
# =====================================================================

function Invoke-QOEmailTicketPoll {

    $s = Get-QOSettings
    if (-not $s.Tickets -or -not $s.Tickets.EmailIntegration) { return @() }
    if (-not [bool]$s.Tickets.EmailIntegration.Enabled) { return @() }

    $mailboxes = @($s.Tickets.EmailIntegration.MonitoredAddresses)
    if (-not $mailboxes -or $mailboxes.Count -lt 1) { return @() }

    # Ensure state bag exists
    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastProcessedByMailbox")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName LastProcessedByMailbox -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $created = @()

    $outlook = $null
    $ns = $null

    try {
        $outlook = New-Object -ComObject Outlook.Application
        $ns = $outlook.GetNamespace("MAPI")

        foreach ($mb in $mailboxes) {

            $mbx = "$mb".Trim()
            if ([string]::IsNullOrWhiteSpace($mbx)) { continue }

            $key = $mbx.ToLower()

            # Load "since"
            $since = $null
            try {
                $raw = $s.Tickets.EmailIntegration.LastProcessedByMailbox.$key
                if ($raw) { $since = [datetime]::Parse("$raw") }
            } catch {}

            if (-not $since) { $since = (Get-Date).AddDays(-3) }

            # Resolve mailbox
            $inbox = $null
            try {
                # If the monitored address is the current Outlook user, use default inbox
                $currentSmtp = $null
                try {
                    $currentSmtp = "$($ns.CurrentUser.Address)".Trim()
                } catch {}

                if ($currentSmtp -and ($currentSmtp.ToLower() -eq $key)) {
                    $inbox = $ns.GetDefaultFolder(6) # olFolderInbox
                }
                else {
                    $r = $ns.CreateRecipient($mbx)
                    [void]$r.Resolve()
                    if (-not $r.Resolved) { continue }
                    $inbox = $ns.GetSharedDefaultFolder($r, 6) # olFolderInbox
                }
            }
            catch {
                continue
            }

            if (-not $inbox) { continue }

            # Pull only MailItems, newest first
            $items = $null
            try {
                $items = $inbox.Items
                $items.Sort("[ReceivedTime]", $true)
            } catch {}

            if (-not $items) { continue }

            $maxSeen = $since

            foreach ($item in @($items)) {

                # Only MailItem (Class 43)
                try {
                    if ($item.Class -ne 43) { continue }
                } catch { continue }

                $rt = $null
                try { $rt = [datetime]$item.ReceivedTime } catch { continue }

                if ($rt -le $since) { break } # sorted desc, can stop here

                if ($rt -gt $maxSeen) { $maxSeen = $rt }

                $subject = ""
                $body    = ""
                $from    = $null

                try { $subject = "$($item.Subject)" } catch {}
                try { $body    = "$($item.Body)" } catch {}
                try { $from    = "$($item.SenderEmailAddress)" } catch {}

                $ticket = New-QOTicket `
                    -Title $subject `
                    -Description $body `
                    -Category "Email" `
                    -Priority "Normal" `
                    -Source "Email" `
                    -RequesterEmail $from `
                    -Tags @("Email", $key)

                $ticket.CreatedAt = $rt
                $ticket.UpdatedAt = $rt

                Add-QOTicket -Ticket $ticket | Out-Null
                $created += $ticket
            }

            # Advance watermark (add 1 second to avoid same-timestamp duplicates)
            $next = $maxSeen.AddSeconds(1)
            $s.Tickets.EmailIntegration.LastProcessedByMailbox |
                Add-Member -NotePropertyName $key -NotePropertyValue ($next.ToString("o")) -Force
        }

        Save-QOSettings -Settings $s
        return $created
    }
    finally {
        # Best-effort COM cleanup
        try { if ($ns) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ns) } } catch {}
        try { if ($outlook) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) } } catch {}
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
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
    Remove-QOTicket, `
    Get-QOTicketById, `
    Invoke-QOEmailTicketPoll
