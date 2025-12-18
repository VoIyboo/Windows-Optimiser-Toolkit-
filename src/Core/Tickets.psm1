# src\Core\Tickets.psm1
# Core ticket storage + model (NO UI CODE IN HERE)

$ErrorActionPreference = "Stop"

# Only import Settings here
# Only import Settings if its functions are not already available
if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) {
    $settingsPath = Join-Path $PSScriptRoot "Settings.psm1"
    Import-Module $settingsPath -Force -ErrorAction Stop
}

function Get-QOTicketsStorePath {
    $s = Get-QOSettings

    if ($s -and $s.PSObject.Properties.Name -contains "TicketStorePath" -and $s.TicketStorePath) {
        return [string]$s.TicketStorePath
    }

    # Safe default if not set yet
    $defaultDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
    return (Join-Path $defaultDir "Tickets.json")
}

function Ensure-QOTicketsStoreDirectory {
    $path = Get-QOTicketsStorePath
    $dir  = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $path
}
# =====================================================================
# AGENT PRESENCE (who has connected to the shared Tickets folder)
# =====================================================================

function Get-QOAgentsStorePath {
    # Agents.json lives next to Tickets.json in the same folder
    $ticketsPath = Get-QOTicketsStorePath
    $dir = Split-Path $ticketsPath -Parent
    return (Join-Path $dir "Agents.json")
}

function Get-QOAgents {
    $path = Get-QOAgentsStorePath

    if (-not (Test-Path $path)) {
        return @()
    }

    $raw = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    try {
        $data = $raw | ConvertFrom-Json
        return @($data)
    } catch {
        return @()
    }
}

function Save-QOAgents {
    param(
        [Parameter(Mandatory)]
        $Agents
    )

    $path = Get-QOAgentsStorePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    @($Agents) | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
}

function Get-QOCurrentTechIdentity {
    # TechId should be stable across machines for the same user (domain\user)
    $techId = $env:USERNAME
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($id -and $id.Name) { $techId = $id.Name }
    } catch { }

    # Friendly display name (fallbacks are fine)
    $display = $env:USERNAME
    try {
        $display = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ToTitleCase($env:USERNAME)
    } catch { }

    $pc = $env:COMPUTERNAME

    [pscustomobject]@{
        TechId       = [string]$techId
        DisplayName  = [string]$display
        ComputerName = [string]$pc
    }
}

function Register-QOAgentPresence {
    $me = Get-QOCurrentTechIdentity
    $agents = @(Get-QOAgents)

    $now = (Get-Date).ToString("o")

    $existing = $agents | Where-Object { [string]$_.TechId -eq $me.TechId } | Select-Object -First 1
    if ($existing) {
        $existing.DisplayName  = $me.DisplayName
        $existing.ComputerName = $me.ComputerName
        $existing.LastSeenUtc  = $now
    } else {
        $agents += [pscustomobject]@{
            TechId       = $me.TechId
            DisplayName  = $me.DisplayName
            ComputerName = $me.ComputerName
            LastSeenUtc  = $now
        }
    }

    Save-QOAgents -Agents $agents
    return $agents
}




function Get-QOTickets {
    $path = Ensure-QOTicketsStoreDirectory

    if (-not (Test-Path $path)) {
        $db = [pscustomobject]@{
            Version   = 1
            UpdatedAt = (Get-Date).ToString("o")
            Tickets   = @()
        }
        $db | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
        return $db
    }

    $raw = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ Version = 1; UpdatedAt = (Get-Date).ToString("o"); Tickets = @() }
    }

    $db = $raw | ConvertFrom-Json

    if (-not ($db.PSObject.Properties.Name -contains "Tickets") -or $null -eq $db.Tickets) {
        $db | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
    }

    $db.Tickets = @($db.Tickets)
    return $db
}

function Save-QOTickets {
    param(
        [Parameter(Mandatory)]
        $Db
    )

    $path = Ensure-QOTicketsStoreDirectory
    $Db.UpdatedAt = (Get-Date).ToString("o")
    $Db | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
}

function New-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [string]$Category = "General",
        [string]$Priority = "Normal"
    )

    [pscustomobject]@{
        Id          = ([guid]::NewGuid().ToString())
        Title       = $Title
        Description = $Description
        Category    = $Category
        Priority    = $Priority
        Status      = "New"
        CreatedAt   = (Get-Date).ToString("o")
        AssignedTo   = 'Unassigned'
        AssignedToId = $null
    }
}

function Add-QOTicket {
    param(
        [Parameter(Mandatory)]
        $Ticket
    )

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Db $db
    return $Ticket
}

function Remove-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Id
    )

    $db = Get-QOTickets
    $before = @($db.Tickets).Count
    $db.Tickets = @($db.Tickets | Where-Object { $_.Id -ne $Id })
    $after = @($db.Tickets).Count

    if ($after -ne $before) {
        Save-QOTickets -Db $db
        return $true
    }

    return $false
}

function Get-QOAgentsDirectory {
    # Ticket store path is the full json file path
    $ticketsJsonPath = Ensure-QOTicketsStoreDirectory
    $rootDir = Split-Path $ticketsJsonPath -Parent

    $agentsDir = Join-Path $rootDir "Agents"
    if (-not (Test-Path $agentsDir)) {
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
    }
    return $agentsDir
}

function Get-QOCurrentAgentInfo {
    $sid = $null
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    } catch { }

    $displayName = $env:USERNAME
    try {
        $u = Get-CimInstance Win32_UserAccount -Filter "Name='$env:USERNAME'" -ErrorAction Stop | Select-Object -First 1
        if ($u -and $u.FullName) { $displayName = [string]$u.FullName }
    } catch { }

    [pscustomobject]@{
        Sid         = [string]$sid
        Username    = [string]$env:USERNAME
        DisplayName = [string]$displayName
        MachineName = [string]$env:COMPUTERNAME
        LastSeenUtc = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Register-QOAgentPresence {
    try {
        $dir = Get-QOAgentsDirectory
        $me = Get-QOCurrentAgentInfo

        if ([string]::IsNullOrWhiteSpace($me.Sid)) {
            $me | Add-Member -NotePropertyName Sid -NotePropertyValue ("USER_" + $me.Username) -Force
        }

        $path = Join-Path $dir ($me.Sid + ".json")

        # Atomic write to avoid half-written JSON
        $tmp = $path + ".tmp"
        $me | ConvertTo-Json -Depth 6 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $path -Force

        return $me
    } catch {
        return $null
    }
}

function Get-QOKnownAgents {
    try {
        $dir = Get-QOAgentsDirectory
        $files = Get-ChildItem -Path $dir -Filter "*.json" -File -ErrorAction SilentlyContinue
        if (-not $files) { return @() }

        $agents = foreach ($f in $files) {
            try {
                Get-Content -Path $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch { }
        }

        return @($agents | Where-Object { $_ -and $_.DisplayName } | Sort-Object DisplayName)
    } catch {
        return @()
    }
}

function Invoke-QOEmailTicketPoll {
    param(
        [int] $MaxItemsPerMailbox = 10
    )

    $mailboxes = @()
    if (Get-Command Get-QOMonitoredEmailAddresses -ErrorAction SilentlyContinue) {
        $mailboxes = @(Get-QOMonitoredEmailAddresses)
    } else {
        $s = Get-QOSettings
        if ($s -and $s.Tickets -and $s.Tickets.EmailIntegration) {
            $mailboxes = @($s.Tickets.EmailIntegration.MonitoredAddresses)
        }
    }
    
    $mailboxes = @(
        $mailboxes |
        Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { ([string]$_).Trim() } |
        Select-Object -Unique
    )
    
    if (-not $mailboxes -or $mailboxes.Count -lt 1) {
        return @()
    }
    
    
        $created = @()
    
        function Get-QOUnreadMailItemsFromFolder {
            param(
                [Parameter(Mandatory)] $Folder,
                [int] $Max = 25
            )

        $out = @()

        try {
            $items = $Folder.Items
            $items.Sort("[ReceivedTime]", $true)

            $restricted = $null
            try { $restricted = $items.Restrict("[UnRead] = true") } catch { $restricted = $items }
            if (-not $restricted) { $restricted = $items }

            $i = 0
            foreach ($m in @($restricted)) {
                if ($i -ge $Max) { break }
                $i++
                if ($m) { $out += $m }
            }
        } catch { }

        return @($out)
    }

    try {
        $outlook = $null
        try { $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject("Outlook.Application") } catch { }
        if (-not $outlook) { $outlook = New-Object -ComObject Outlook.Application }

        $ns = $outlook.GetNamespace("MAPI")

        foreach ($addr in $mailboxes) {

            $inbox = $null

            try {
                foreach ($store in @($ns.Folders)) {
                    try {
                        $storeSmtp = $null
                        try {
                            $storeSmtp = $store.Store.PropertyAccessor.GetProperty("http://schemas.microsoft.com/mapi/proptag/0x0C1F001E")
                        } catch { $storeSmtp = $null }

                        if ($storeSmtp -and ([string]$storeSmtp).ToLower() -eq ([string]$addr).ToLower()) {
                            try { $inbox = $store.Folders.Item("Inbox") } catch { $inbox = $null }
                            if ($inbox) { break }
                        }
                    } catch { }
                }
            } catch { }

            if (-not $inbox) {
                try {
                    foreach ($root in @($ns.Folders)) {
                        try {
                            $candidate = $null
                            try { $candidate = $root.Folders.Item("Inbox") } catch { $candidate = $null }
                            if ($candidate) { $inbox = $candidate; break }
                        } catch { }
                    }
                } catch { }
            }

            if (-not $inbox) { continue }

            $foldersToScan = @()
            $foldersToScan += $inbox

            try {
                foreach ($sub in @($inbox.Folders)) {
                    if ($sub) { $foldersToScan += $sub }
                }
            } catch { }

            $count = 0

            foreach ($folder in $foldersToScan) {

                $unreadItems = @(Get-QOUnreadMailItemsFromFolder -Folder $folder -Max $MaxItemsPerMailbox)

                foreach ($m in $unreadItems) {

                    if ($count -ge $MaxItemsPerMailbox) { break }

                    try {
                        if (-not $m.Subject) { continue }

                        $msgId = $null
                        try { $msgId = [string]$m.EntryID } catch { $msgId = $null }

                        $db = Get-QOTickets
                        $existing = $null

                        if ($msgId) {
                            $existing = @($db.Tickets) | Where-Object {
                                $_.PSObject.Properties.Name -contains "SourceMessageId" -and
                                [string]$_.SourceMessageId -eq $msgId
                            } | Select-Object -First 1
                        }

                        if ($existing) { continue }

                        $body = ""
                        try { $body = [string]$m.Body } catch { $body = "" }

                        $t = New-QOTicket -Title ([string]$m.Subject) -Description $body -Category "Email" -Priority "Normal"
                        $t | Add-Member -NotePropertyName SourceMailbox   -NotePropertyValue ([string]$addr) -Force
                        $t | Add-Member -NotePropertyName SourceMessageId -NotePropertyValue ([string]$msgId) -Force
                        $t | Add-Member -NotePropertyName ReceivedAt      -NotePropertyValue ((Get-Date).ToString("o")) -Force
                        try { $t | Add-Member -NotePropertyName SourceFolder -NotePropertyValue ([string]$folder.Name) -Force } catch { }

                        Add-QOTicket -Ticket $t | Out-Null
                        $created += $t
                        $count++

                        try {
                            $m.UnRead = $false
                            $m.Save()
                        } catch { }

                    } catch { }
                }

                if ($count -ge $MaxItemsPerMailbox) { break }
            }
        }

    } catch {
        return @()
    }

    return @($created)
}

Export-ModuleMember -Function `
    Get-QOTickets, Save-QOTickets, `
    Get-QOTicketsStorePath, Ensure-QOTicketsStoreDirectory, `
    Add-QOTicket, Remove-QOTicket, New-QOTicket, `
    Invoke-QOEmailTicketPoll
