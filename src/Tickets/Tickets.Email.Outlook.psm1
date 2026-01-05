# src\Tickets\Tickets.Email.Outlook.psm1
# Outlook COM sync for QOT tickets (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import core tickets module so this module can call:
# Get-QOTMonitoredMailboxAddresses, Get-QOTickets, Add-QOTicket
try {
    Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Force -ErrorAction Stop
} catch {
    throw ("Failed to import Core Tickets module: " + $_.Exception.Message)
}

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw "PowerShell is not running in STA mode. Launch with: powershell.exe -STA"
}

function Get-QOTOutlookNamespace {
    try {
        $outlook = New-Object -ComObject Outlook.Application
        return $outlook.GetNamespace("MAPI")
    } catch {
        throw ("Outlook COM failed: " + $_.Exception.Message)
    }
}

function Get-QOTMailboxInboxFolder {
    param(
        [Parameter(Mandatory)]
        [object]$MAPI,
        [Parameter(Mandatory)]
        [string]$MailboxAddress
    )

    $olFolderInbox = 6

    try {
        $recipient = $MAPI.CreateRecipient($MailboxAddress)
        $recipient.Resolve() | Out-Null

        if (-not $recipient.Resolved) {
            throw "Recipient not resolved: $MailboxAddress"
        }

        return $MAPI.GetSharedDefaultFolder($recipient, $olFolderInbox)
    } catch {
        throw "Cannot open Inbox for $MailboxAddress. Check Outlook permissions and that the mailbox exists in your profile."
    }
}

# ---------------------------------------------------------------------
# Watermark: only sync emails newer than last successful sync
# Stored in Settings: Tickets.EmailIntegration.LastSyncUtc
# ---------------------------------------------------------------------
function Get-QOTLastEmailSyncUtc {
    try {
        $s = Get-QOSettings
        if ($s -and $s.PSObject.Properties.Name -contains "Tickets") {
            $t = $s.Tickets
            if ($t -and $t.PSObject.Properties.Name -contains "EmailIntegration") {
                $ei = $t.EmailIntegration
                if ($ei -and $ei.PSObject.Properties.Name -contains "LastSyncUtc") {
                    $v = [string]$ei.LastSyncUtc
                    if (-not [string]::IsNullOrWhiteSpace($v)) {
                        return ([datetime]::Parse($v)).ToUniversalTime()
                    }
                }
            }
        }
    } catch { }

    return [datetime]"1970-01-01T00:00:00Z"
}

function Set-QOTLastEmailSyncUtc {
    param(
        [Parameter(Mandatory)]
        [datetime]$UtcTime
    )

    try {
        $s = Get-QOSettings
        if (-not $s) { return }

        if ($s.PSObject.Properties.Name -notcontains "Tickets") {
            $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        if ($s.Tickets.PSObject.Properties.Name -notcontains "EmailIntegration") {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        $s.Tickets.EmailIntegration.LastSyncUtc = $UtcTime.ToUniversalTime().ToString("o")
        Save-QOSettings -Settings $s
    } catch { }
}

function Convert-QOTMailItemToTicket {
    param(
        [Parameter(Mandatory)] [string]$MailboxAddress,
        [Parameter(Mandatory)] [object]$MailItem
    )

    $from = ""
    try { $from = [string]$MailItem.SenderEmailAddress } catch { }
    if (-not $from) {
        try { $from = [string]$MailItem.SenderName } catch { }
    }

    $subject = ""
    try { $subject = [string]$MailItem.Subject } catch { }

    $received = $null
    try { $received = [datetime]$MailItem.ReceivedTime } catch { $received = Get-Date }

    $body = ""
    try { $body = [string]$MailItem.Body } catch { }

    $entryId = ""
    try { $entryId = [string]$MailItem.EntryID } catch { }

    $internetId = ""
    try {
        $internetId = [string]$MailItem.PropertyAccessor.GetProperty(
            "http://schemas.microsoft.com/mapi/string/{00020386-0000-0000-C000-000000000046}/InternetMessageId"
        )
    } catch { }

    $sourceId = if ($internetId) { $internetId } else { $entryId }

    # Clean up noisy subjects
    $cleanTitle = ($subject + "").Trim()
    if ($cleanTitle) {
        $cleanTitle = $cleanTitle -replace '^(RE|FW|FWD):\s*', ''
        $cleanTitle = $cleanTitle -replace '\*\*DO NOT REPLY\*\*', ''
        $cleanTitle = $cleanTitle.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($cleanTitle)) {
        $cleanTitle = "(No subject)"
    }

    # Optional: basic priority hints
    $priority = "Normal"
    try {
        if ($cleanTitle -match '(?i)\b(urgent|asap|immediately|critical|sev)\b') { $priority = "High" }
        elseif ($cleanTitle -match '(?i)\b(password|login|access|mfa|2fa|locked)\b') { $priority = "High" }
    } catch { }

    $createdStr = $received.ToString("yyyy-MM-dd HH:mm:ss")

    return [pscustomobject]@{
        Id              = ([guid]::NewGuid().ToString())

        Title           = $cleanTitle
        Created         = $createdStr
        CreatedAt       = $createdStr
        Status          = "New"
        Priority        = $priority

        Source          = "Outlook"
        SourceMailbox   = $MailboxAddress
        SourceMessageId = $sourceId

        EmailFrom       = if ($from) { $from } else { "Unknown sender" }
        EmailReceived   = $createdStr
        EmailBody       = $body
    }
}

function Sync-QOTicketsFromOutlook {
    param(
        [int]$MaxPerMailbox = 200,
        [switch]$MarkAsRead,
        [string]$ProcessedCategory = "QOT Imported"
    )

    $mailboxes = Get-QOTMonitoredMailboxAddresses
    if (-not $mailboxes -or $mailboxes.Count -eq 0) {
        return [pscustomobject]@{ Added = 0; Note = "No monitored mailbox addresses set." }
    }

    $existingDb  = Get-QOTickets
    $existingIds = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($t in @($existingDb.Tickets)) {
        try {
            if ($t.SourceMessageId) { [void]$existingIds.Add([string]$t.SourceMessageId) }
        } catch { }
    }

    $lastSyncUtc = Get-QOTLastEmailSyncUtc
    $mapi  = Get-QOTOutlookNamespace
    $added = 0

    foreach ($mb in $mailboxes) {
        $inbox = Get-QOTMailboxInboxFolder -MAPI $mapi -MailboxAddress $mb

        $items = $inbox.Items
        try { $items.Sort("[ReceivedTime]", $true) } catch { }

        # Restrict to only new emails since last sync (Outlook expects local time formatting)
        $localCutoff = $lastSyncUtc.ToLocalTime().ToString("g")
        $filter = "[ReceivedTime] > '$localCutoff'"

        try {
            $items = $items.Restrict($filter)
        } catch { }

        $count = 0
        foreach ($item in @($items)) {
            if ($count -ge $MaxPerMailbox) { break }

            $isMail = $false
            try { $isMail = ($item.MessageClass -like "IPM.Note*") } catch { }
            if (-not $isMail) { continue }

            $categories = ""
            try { $categories = [string]$item.Categories } catch { }

            if ($ProcessedCategory -and $categories -and $categories -like "*$ProcessedCategory*") {
                continue
            }

            $ticket = Convert-QOTMailItemToTicket -MailboxAddress $mb -MailItem $item
            if (-not $ticket.SourceMessageId) { continue }

            if ($existingIds.Contains([string]$ticket.SourceMessageId)) {
                continue
            }

            Add-QOTicket -Ticket $ticket
            [void]$existingIds.Add([string]$ticket.SourceMessageId)

            try {
                if ($ProcessedCategory) {
                    if ($categories) { $item.Categories = ($categories + "; " + $ProcessedCategory) } else { $item.Categories = $ProcessedCategory }
                }
                if ($MarkAsRead) { $item.UnRead = $false }
                $item.Save() | Out-Null
            } catch { }

            $added++
            $count++
        }
    }

    # Only update watermark after completing all mailboxes
    Set-QOTLastEmailSyncUtc -UtcTime (Get-Date)

    return [pscustomobject]@{ Added = $added; Note = ("Sync complete. CutoffUtc=" + $lastSyncUtc.ToString("o")) }
}

Export-ModuleMember -Function Sync-QOTicketsFromOutlook
