# Tickets.psm1
# Storage + email ingestion for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

# =====================================================================
# STORAGE PATHS
# =====================================================================

$script:TicketStorePath  = $null
$script:TicketBackupPath = $null

function Initialize-QOTicketStorage {

    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $s = Get-QOSettings

    if (-not ($s.PSObject.Properties.Name -contains "TicketStorePath")) {
        $s | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $null -Force
    }
    if (-not ($s.PSObject.Properties.Name -contains "LocalTicketBackupPath")) {
        $s | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue $null -Force
    }

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

        $db.Tickets = @($db.Tickets)
        return $db
    }
    catch {
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

# =====================================================================
# EMAIL -> TICKET POLLER (OUTLOOK COM)
# =====================================================================

$script:EmailPollLog = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\EmailPoll.log"

function Write-QOEmailPollLog {
    param([string]$Message)

    try {
        $dir = Split-Path -Parent $script:EmailPollLog
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -LiteralPath $script:EmailPollLog -Value $line -Encoding UTF8
    } catch {}
}

function Get-QOCurrentSmtpAddress {
    param([Parameter(Mandatory)] $Namespace)

    try {
        $ae = $Namespace.CurrentUser.AddressEntry
        if ($ae) {
            $ex = $ae.GetExchangeUser()
            if ($ex -and $ex.PrimarySmtpAddress) { return [string]$ex.PrimarySmtpAddress }
        }
    } catch {}

    return $null
}

function Get-QOInboxFolder {
    param(
        [Parameter(Mandatory)] $Namespace,
        [Parameter(Mandatory)] [string] $Mailbox
    )

    $mb = ""
    if ($null -ne $Mailbox) { $mb = [string]$Mailbox }
    $mb = $mb.Trim()
    if ([string]::IsNullOrWhiteSpace($mb)) { return $null }

    $me = Get-QOCurrentSmtpAddress -Namespace $Namespace

    # Always try default inbox first (most reliable)
    try {
        if ($me -and ($me.Trim().ToLower() -eq $mb.ToLower())) {
            Write-QOEmailPollLog "Inbox resolve: using DEFAULT inbox for $mb"
            return $Namespace.GetDefaultFolder(6)
        }
    } catch {}

    # Shared inbox path (shared mailbox access)
    try {
        $r = $Namespace.CreateRecipient($mb)
        $null = $r.Resolve()
        if ($r -and $r.Resolved) {
            Write-QOEmailPollLog "Inbox resolve: using SHARED inbox for $mb"
            return $Namespace.GetSharedDefaultFolder($r, 6)
        }
    } catch {}

    # Folder tree fallback
    try {
        $root = $Namespace.Folders.Item($mb)
        if ($root) {
            $inbox = $root.Folders.Item("Inbox")
            if ($inbox) {
                Write-QOEmailPollLog "Inbox resolve: using TREE inbox for $mb"
                return $inbox
            }
        }
    } catch {}

    Write-QOEmailPollLog "Inbox resolve: FAILED for $mb (me=$me)"
    return $null
}

function Invoke-QOEmailTicketPoll {

    $s = Get-QOSettings

    if (-not $s.Tickets) { Write-QOEmailPollLog "Settings: Tickets missing"; return @() }
    if (-not $s.Tickets.EmailIntegration) { Write-QOEmailPollLog "Settings: EmailIntegration missing"; return @() }
    if (-not [bool]$s.Tickets.EmailIntegration.Enabled) { Write-QOEmailPollLog "Settings: EmailIntegration disabled"; return @() }

    $mailboxes = @()
    if ($s.Tickets.EmailIntegration.MonitoredAddresses) {
        $mailboxes = @($s.Tickets.EmailIntegration.MonitoredAddresses) |
            Where-Object { $_ } |
            ForEach-Object { "$_".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    if ($mailboxes.Count -lt 1) {
        Write-QOEmailPollLog "Settings: No monitored addresses"
        return @()
    }

    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastProcessedByMailbox")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName LastProcessedByMailbox -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    Write-QOEmailPollLog "Poll start. Mailboxes: $($mailboxes -join ', ')"

    $created = @()

    $outlook = $null
    $ns = $null
    try {
        $outlook = New-Object -ComObject Outlook.Application
        $ns      = $outlook.GetNamespace("MAPI")
    } catch {
        Write-QOEmailPollLog "Outlook COM failed: $($_.Exception.Message)"
        return @()
    }

    foreach ($mb in $mailboxes) {

        $key = $mb.Trim().ToLower()

        $since = $null
        try {
            $raw = $s.Tickets.EmailIntegration.LastProcessedByMailbox.$key
            if ($raw) { $since = [datetime]::Parse([string]$raw) }
        } catch {}

        if (-not $since) { $since = (Get-Date).AddDays(-3) }

        Write-QOEmailPollLog "Mailbox $mb since $($since.ToString('o'))"

        $inbox = Get-QOInboxFolder -Namespace $ns -Mailbox $mb
        if (-not $inbox) { continue }

        $items = $null
        try { $items = $inbox.Items } catch { $items = $null }
        if (-not $items) { Write-QOEmailPollLog "Mailbox $mb: inbox.Items failed"; continue }

        try { $items.Sort("[ReceivedTime]", $true) } catch {}

        $latestSeen = $since
        $scanLimit = 100
        $count = 0

        for ($i = 1; $i -le $items.Count; $i++) {

            $count++
            if ($count -gt $scanLimit) { break }

            $mail = $null
            try { $mail = $items.Item($i) } catch { continue }
            if (-not $mail) { continue }

            # MailItem only
            try { if ($mail.Class -ne 43) { continue } } catch { continue }

            $rt = $null
            try { $rt = $mail.ReceivedTime } catch { $rt = $null }
            if (-not $rt) { continue }

            if ($rt -le $since) { break }

            if ($rt -gt $latestSeen) { $latestSeen = $rt }

            $subject = ""
            $body    = ""
            $from    = ""

            try { $subject = [string]$mail.Subject } catch {}
            try { $body    = [string]$mail.Body } catch {}

            try {
                $from = [string]$mail.SenderEmailAddress
                if ([string]::IsNullOrWhiteSpace($from)) { $from = [string]$mail.SenderName }
            } catch {}

            $title = $subject
            if ([string]::IsNullOrWhiteSpace($title)) { $title = "(No subject)" }

            Write-QOEmailPollLog "Creating ticket from email. Mailbox=$mb Received=$($rt.ToString('o')) Subject=$title From=$from"

            $ticket = New-QOTicket `
                -Title $title `
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

        if ($latestSeen -and $latestSeen -gt $since) {
            $s.Tickets.EmailIntegration.LastProcessedByMailbox |
                Add-Member -NotePropertyName $key -NotePropertyValue ($latestSeen.ToString("o")) -Force
            Write-QOEmailPollLog "Mailbox $mb updated last processed to $($latestSeen.ToString('o'))"
        } else {
            Write-QOEmailPollLog "Mailbox $mb: no new mail found"
        }
    }

    Save-QOSettings -Settings $s

    Write-QOEmailPollLog "Poll end. Created $($created.Count) ticket(s)."
    return $created
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
    Invoke-QOEmailTicketPoll
