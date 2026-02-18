# src\Tickets\Tickets.UI.psm1
# UI wiring for Tickets tab (NO core logic in here)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\Core\Logging\Logging.psm1") -Force -ErrorAction SilentlyContinue

# -------------------------
# State
# -------------------------
$script:TicketsGrid = $null
$script:TicketsEmailSyncInProgress = $false
$script:TicketsContentRenderedHandler = $null
$script:TicketsSyncStatusText = $null
$script:TicketsSyncWorkerStarted = $false
$script:TicketsSyncFailureCount = 0
$script:TicketsSyncNextAttemptUtc = [datetime]::MinValue
$script:TicketsLastSuccessfulSyncUtc = $null
$script:TicketsSyncTimer = $null

# Stored handlers to avoid double wiring
$script:TicketsLoadedHandler  = $null
$script:TicketsNewHandler     = $null
$script:TicketsDeleteHandler  = $null
$script:TicketsToggleDetailsHandler = $null
$script:TicketsSelectionChangedHandler = $null
$script:TicketsRowEditHandler = $null
$script:TicketsSendReplyHandler = $null
$script:TicketsFilterButtonHandler = $null
$script:TicketsSyncWorkerTickHandler = $null
$script:TicketsUndeleteHandler = $null

$script:TicketsFileWatcher = $null
$script:TicketsFileWatcherEvents = @()
$script:TicketsFileRefreshTimer = $null
$script:TicketsCurrentView = "Filtered"
$script:TicketsFilterState = $null
$script:TicketsFilterMenu = $null
$script:TicketsFilterOpenCheckbox = $null
$script:TicketsFilterClosedCheckbox = $null
$script:TicketsFilterDeletedCheckbox = $null
$script:TicketsFilterCheckboxHandler = $null
$script:AllTickets = $null
$script:TicketsFilterDefaults = [pscustomobject]@{
    ShowOpen    = $true
    ShowClosed  = $true
    ShowDeleted = $false
}
$script:ShowOpen = $true
$script:ShowClosed = $true
$script:ShowDeleted = $false

function Write-QOTicketsUILog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    try {
        switch ($Level) {
            'ERROR' { if (Get-Command Write-QOTLogError -ErrorAction SilentlyContinue) { Write-QOTLogError $Message; return } }
            'WARN'  { if (Get-Command Write-QOTLogWarn  -ErrorAction SilentlyContinue) { Write-QOTLogWarn  $Message; return } }
            default { if (Get-Command Write-QOTLogInfo  -ErrorAction SilentlyContinue) { Write-QOTLogInfo  $Message; return } }
        }
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
            return
        }
    } catch { }

    # absolute fallback, never crash the UI
    try { Write-Host ("[Tickets.UI] " + $Level + ": " + $Message) } catch { }
}

Write-QOTicketsUILog "=== Tickets.UI.psm1 LOADED ==="

function Get-QOTicketsDefaultFilterState {
    return [pscustomobject]@{
        ShowOpen    = [bool]$script:TicketsFilterDefaults.ShowOpen
        ShowClosed  = [bool]$script:TicketsFilterDefaults.ShowClosed
        ShowDeleted = [bool]$script:TicketsFilterDefaults.ShowDeleted
    }
}

function Get-QOTicketsFilterState {
    if (-not $script:TicketsFilterState) {
        $script:TicketsFilterState = Get-QOTicketsDefaultFilterState
    }

    foreach ($prop in @("ShowOpen", "ShowClosed", "ShowDeleted")) {
        if ($script:TicketsFilterState.PSObject.Properties.Name -notcontains $prop) {
            $script:TicketsFilterState | Add-Member -NotePropertyName $prop -NotePropertyValue (Get-QOTicketsDefaultFilterState.$prop) -Force
        }
        if ($null -eq $script:TicketsFilterState.$prop) {
            $script:TicketsFilterState.$prop = Get-QOTicketsDefaultFilterState.$prop
        }
    }

    return $script:TicketsFilterState
}

function Write-QOTicketsFilterLog {
    param(
        [bool]$Open,
        [bool]$Closed,
        [bool]$Deleted
    )

    $message = ("Tickets filter updated: Open={0}, Closed={1}, Deleted={2}" -f $Open, $Closed, $Deleted)
    try {
        if (Get-Command Write-QOTLogInfo -ErrorAction SilentlyContinue) {
            Write-QOTLogInfo $message
            return
        }
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $message "INFO"
            return
        }
    } catch { }

    try { Write-Host ("[Tickets.UI] INFO: " + $message) } catch { }
}

function Get-QOTicketsAllItems {
    try {
        $items = $null
        if (Get-Command Get-QOTickets -ErrorAction SilentlyContinue) {
            $items = Get-QOTickets
        }

        if ($null -eq $items) { return @() }

        if ($items.PSObject.Properties.Name -contains "Tickets") {
            $tickets = @($items.Tickets)
            Write-QOTicketsUILog ("Tickets: Loaded {0} items for grid (Tickets property)." -f $tickets.Count)
            return $tickets
        }

        $list = @($items)
        Write-QOTicketsUILog ("Tickets: Loaded {0} items for grid (direct)." -f $list.Count)
        return $list
    }
    catch {
        $msg = $_.Exception.Message
        $stack = $_.Exception.StackTrace
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { "" }

        Write-QOTicketsUILog ("Tickets: Load failed. Error: " + $msg) "ERROR"
        if ($inner) { Write-QOTicketsUILog ("Tickets: InnerException: " + $inner) "ERROR" }
        if ($stack) { Write-QOTicketsUILog ("Tickets: StackTrace: " + $stack) "ERROR" }

        $popupMessage = "Tickets failed to load.`n`nError: " + $msg
        if ($inner) { $popupMessage += "`nInner: " + $inner }
        [System.Windows.MessageBox]::Show(
            $popupMessage,
            "Quinn Optimiser Toolkit",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return @()
    }
}

function Get-QOTicketsVisibleItems {
    param(
        [object[]]$Items,
        [Parameter(Mandatory)]$FilterState
    )

    $showOpen = [bool]$FilterState.ShowOpen
    $showClosed = [bool]$FilterState.ShowClosed
    $showDeleted = [bool]$FilterState.ShowDeleted

    if (-not ($showOpen -or $showClosed -or $showDeleted)) {
        return @()
    }

    return @(
        $Items |
            Where-Object {
                if ($null -eq $_) { return $false }

                $isDeleted = $false
                try { $isDeleted = [bool]$_.IsDeleted } catch { $isDeleted = $false }
                $statusValue = ""
                try {
                    if ($_.PSObject.Properties.Name -contains "Status") {
                        $statusValue = [string]$_.Status
                    }
                } catch { }
                $isClosed = ($statusValue -eq "Closed" -or $statusValue -eq "Completed")
                $isOpen = (-not $isDeleted) -and (-not $isClosed)

                ($showOpen -and $isOpen) -or
                ($showClosed -and (-not $isDeleted) -and $isClosed) -or
                ($showDeleted -and $isDeleted)
            }
    )
}

function New-QOTicketsObservableCollection {
    param([object[]]$Items)

    $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($item in @($Items)) {
        $collection.Add($item) | Out-Null
    }
    return $collection
}

function Apply-TicketsFilter {
    if (-not $script:TicketsGrid) { return }

    if (-not $script:AllTickets) {
        $script:AllTickets = @(Get-QOTicketsAllItems)
    }
    $filterState = [pscustomobject]@{
        ShowOpen    = [bool]$script:ShowOpen
        ShowClosed  = [bool]$script:ShowClosed
        ShowDeleted = [bool]$script:ShowDeleted
    }

    $filtered = @(Get-QOTicketsVisibleItems -Items $script:AllTickets -FilterState $filterState)
    $script:TicketsGrid.ItemsSource = (New-QOTicketsObservableCollection -Items $filtered)
    $script:TicketsGrid.Items.Refresh()
}

function Invoke-QOTicketsFilterSafely {
    param(
        [switch]$ForceRefresh
    )

    $filterCommand = Get-Command -Name "Apply-TicketsFilter" -ErrorAction SilentlyContinue
    if (-not $filterCommand) {
        Write-QOTicketsUILog "Tickets: Apply-TicketsFilter is unavailable; skipping filter and continuing." "WARN"
        if ($ForceRefresh -and $script:TicketsGrid) {
            try { $script:TicketsGrid.Items.Refresh() } catch { }
        }
        return $false
    }

    try {
        & $filterCommand
        return $true
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Apply-TicketsFilter failed; skipping filter. " + $_.Exception.Message) "WARN"
        if ($ForceRefresh -and $script:TicketsGrid) {
            try { $script:TicketsGrid.Items.Refresh() } catch { }
        }
        return $false
    }
}

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$View
    )

    try {
        Write-QOTicketsUILog "Tickets: Grid refresh started."
        $script:AllTickets = @(Get-QOTicketsAllItems)
        Invoke-QOTicketsFilterSafely -ForceRefresh
        $sourceType = $null
        try { $sourceType = $Grid.ItemsSource.GetType().FullName } catch { }

        $gridCount = 0
        try { $gridCount = $Grid.Items.Count } catch { }

        Write-QOTicketsUILog ("Tickets: ItemsSource set. Type={0}; Items={1}; GridCount={2}" -f $sourceType, $gridCount, $gridCount)
        Write-QOTicketsUILog "Tickets: Grid refresh completed."
    }
    catch {
        $msg = $_.Exception.Message
        $stack = $_.Exception.StackTrace
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { "" }

        Write-QOTicketsUILog ("Tickets: Grid refresh failed. Error: " + $msg) "ERROR"
        if ($inner) { Write-QOTicketsUILog ("Tickets: InnerException: " + $inner) "ERROR" }
        if ($stack) { Write-QOTicketsUILog ("Tickets: StackTrace: " + $stack) "ERROR" }

        $popupMessage = "Load tickets failed.`n`nError: " + $msg
        if ($inner) { $popupMessage += "`nInner: " + $inner }
        [System.Windows.MessageBox]::Show(
            $popupMessage,
            "Quinn Optimiser Toolkit",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

function Set-QOTicketDetailsVisibility {
    param(
        [AllowNull()][System.Windows.UIElement]$DetailsPanel,
        [AllowNull()][System.Windows.Controls.TextBlock]$Chevron,
        [bool]$IsOpen
    )

    if ($DetailsPanel) {
        $DetailsPanel.Visibility = if ($IsOpen) { "Visible" } else { "Collapsed" }
    }
    if ($Chevron) {
        $Chevron.Text = if ($IsOpen) { "" } else { "" }
    }
}

function Update-QOTicketDetailsView {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][System.Windows.UIElement]$DetailsPanel,
        [AllowNull()][System.Windows.Controls.TextBlock]$BodyText,
        [AllowNull()][System.Windows.Controls.TextBox]$ReplySubject,
        [AllowNull()][System.Windows.Controls.TextBox]$ReplyText,
        [AllowNull()][System.Windows.Controls.Button]$ReplyButton,
        [AllowNull()][System.Windows.Controls.TextBlock]$Chevron
    )

    if (-not $Ticket) {
        if ($BodyText) { $BodyText.Text = "Select a ticket to view details." }
        if ($ReplySubject) { $ReplySubject.Text = "" }
        if ($ReplyText) { $ReplyText.Text = "" }
        if ($ReplyButton) { $ReplyButton.IsEnabled = $false }
        Set-QOTicketDetailsVisibility -DetailsPanel $DetailsPanel -Chevron $Chevron -IsOpen:$false
        return
    }

    $body = ""
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailBody") {
            $body = [string]$Ticket.EmailBody
        } elseif ($Ticket.PSObject.Properties.Name -contains "Body") {
            $body = [string]$Ticket.Body
        }
    } catch { }

    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = "No email body found for this ticket."
    }

    if ($BodyText) { $BodyText.Text = $body }
        if ($ReplySubject) {
        $subjectValue = ""
        try {
            if ($Ticket.PSObject.Properties.Name -contains "Subject") {
                $subjectValue = [string]$Ticket.Subject
            } elseif ($Ticket.PSObject.Properties.Name -contains "Title") {
                $subjectValue = [string]$Ticket.Title
            }
        } catch { }

        if ($subjectValue) {
            if ($subjectValue -notmatch '^(RE|FW|FWD):') {
                $subjectValue = "RE: " + $subjectValue
            }
        }

        $ReplySubject.Text = $subjectValue
    }
    if ($ReplyButton) {
        $canReply = $false
        try {
            if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
                if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.SourceMessageId)) { $canReply = $true }
            }
            if (-not $canReply -and ($Ticket.PSObject.Properties.Name -contains "EmailMessageId")) {
                if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.EmailMessageId)) { $canReply = $true }
            }
        } catch { $canReply = $false }

        $ReplyButton.IsEnabled = $canReply
    }
    Set-QOTicketDetailsVisibility -DetailsPanel $DetailsPanel -Chevron $Chevron -IsOpen:$true
}

function Get-QOParentVisual {
    param(
        [AllowNull()]$Element,
        [Parameter(Mandatory)][Type]$Type
    )

    $current = $Element
    while ($current -and -not $Type.IsInstanceOfType($current)) {
        $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
    }
    return $current
}

function Test-QOTProcessElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Set-QOTicketsSyncStatus {
    param(
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [string]$Message
    )

    if (-not $StatusText) { return }
    try {
        if ($StatusText.Dispatcher.CheckAccess()) {
            $StatusText.Text = $Message
        } else {
            $StatusText.Dispatcher.Invoke([action]{ $StatusText.Text = $Message })
        }
    } catch { }
}

function Get-QOTicketDedupKey {
    param([Parameter(Mandatory)]$Ticket)

    try {
        if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
            $id = ([string]$Ticket.SourceMessageId).Trim()
            if ($id) { return ("msg:" + $id.ToLowerInvariant()) }
        }
    } catch { }

    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
            $id = ([string]$Ticket.EmailMessageId).Trim()
            if ($id) { return ("msg:" + $id.ToLowerInvariant()) }
        }
    } catch { }

    $subject = ""
    $received = ""
    try { if ($Ticket.PSObject.Properties.Name -contains "Subject") { $subject = ([string]$Ticket.Subject).Trim().ToLowerInvariant() } } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailReceived") {
            $received = ([string]$Ticket.EmailReceived).Trim().ToLowerInvariant()
        } elseif ($Ticket.PSObject.Properties.Name -contains "CreatedAt") {
            $received = ([string]$Ticket.CreatedAt).Trim().ToLowerInvariant()
        }
    } catch { }

    if (-not $subject -and -not $received) { return "" }
    return ("hash:{0}|{1}" -f $subject, $received)
}

function Merge-QOTicketsIntoGridCollection {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [object[]]$IncomingTickets
    )

    if (-not $Grid -or -not $IncomingTickets -or $IncomingTickets.Count -eq 0) { return 0 }

    if (-not $script:AllTickets) {
        $script:AllTickets = @(Get-QOTicketsAllItems)
    }

    $existingKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($ticket in @($script:AllTickets)) {
        if (-not $ticket) { continue }
        $key = Get-QOTicketDedupKey -Ticket $ticket
        if ($key) { [void]$existingKeys.Add($key) }
    }

    $addedCount = 0
    foreach ($ticket in @($IncomingTickets)) {
        if (-not $ticket) { continue }
        $key = Get-QOTicketDedupKey -Ticket $ticket
        if ($key -and $existingKeys.Contains($key)) { continue }

        $script:AllTickets += @($ticket)
        if ($key) { [void]$existingKeys.Add($key) }

        $visible = @(Get-QOTicketsVisibleItems -Items @($ticket) -FilterState ([pscustomobject]@{
            ShowOpen    = [bool]$script:ShowOpen
            ShowClosed  = [bool]$script:ShowClosed
            ShowDeleted = [bool]$script:ShowDeleted
        }))

        if ($visible.Count -gt 0) {
            $itemsSource = $Grid.ItemsSource
            if ($itemsSource -is [System.Collections.ObjectModel.ObservableCollection[object]]) {
                $itemsSource.Add($ticket) | Out-Null
            } else {
                Invoke-QOTicketsFilterSafely -ForceRefresh
            }
        }
        $addedCount++
    }

    if ($addedCount -gt 0) {
        try { $Grid.Items.Refresh() } catch { }
    }

    return $addedCount
}

function Get-QOTicketsSyncBackoffSeconds {
    param([int]$FailureCount)

    switch ($FailureCount) {
        { $_ -le 1 } { return 120 }
        2 { return 300 }
        3 { return 600 }
        default { return 900 }
    }
}

function Start-TicketsEmailSyncAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [int]$TimeoutSeconds = 20
    )

    if ($script:TicketsEmailSyncInProgress) { return }

    $script:TicketsEmailSyncInProgress = $true
    Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Background sync running..."

    $worker = [System.ComponentModel.BackgroundWorker]::new()
    $worker.WorkerSupportsCancellation = $false

    $worker.DoWork += {
        param($sender, $args)

        $syncScript = {
            param($syncCmdName, $isElevated)
            if ($isElevated) {
                return [pscustomobject]@{ Success = $false; Note = "Elevated session - Outlook COM unavailable"; Added = 0; AddedTickets = @() }
            }
            
            try {
                $syncResult = & $syncCmdName
                if (-not $syncResult) {
                    return [pscustomobject]@{ Success = $false; Note = "Outlook sync returned nothing."; Added = 0; AddedTickets = @() }
                }

                $note = ""
                $added = 0
                $addedTickets = @()
                try { if ($syncResult.PSObject.Properties.Name -contains "Note") { $note = [string]$syncResult.Note } } catch { }
                try { if ($syncResult.PSObject.Properties.Name -contains "Added") { $added = [int]$syncResult.Added } } catch { }
                try { if ($syncResult.PSObject.Properties.Name -contains "AddedTickets") { $addedTickets = @($syncResult.AddedTickets) } } catch { }

                return [pscustomobject]@{ Success = $true; Note = $note; Added = $added; AddedTickets = @($addedTickets) }
            } catch {
                return [pscustomobject]@{ Success = $false; Note = $_.Exception.Message; Added = 0; AddedTickets = @() }
            }
        }

        $ps = [powershell]::Create()
        try {
            $isElevated = Test-QOTProcessElevated
            $null = $ps.AddScript($syncScript).AddArgument($SyncCmd.Name).AddArgument($isElevated)
            $async = $ps.BeginInvoke()

            if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
                try { $ps.Stop() } catch { }
                $args.Result = [pscustomobject]@{ TimedOut = $true; Success = $false; Note = "Outlook unavailable"; Added = 0; AddedTickets = @() }
                return
            }

            $out = $ps.EndInvoke($async)
            if ($out -and $out.Count -gt 0) {
                $args.Result = $out[-1]
            } else {
                $args.Result = [pscustomobject]@{ TimedOut = $false; Success = $false; Note = "Outlook sync returned nothing."; Added = 0; AddedTickets = @() }
            }
        } finally {
            try { $ps.Dispose() } catch { }
        }
    }
    $worker.RunWorkerCompleted += {
        param($sender, $args)

        $script:TicketsEmailSyncInProgress = $false

        $result = $args.Result
        $timedOut = $false
        $success = $false
        $added = 0
        $note = ""
        $addedTickets = @()

        try { if ($args.Error) { $note = [string]$args.Error.Exception.Message } } catch { }
        try { if ($result.PSObject.Properties.Name -contains "TimedOut") { $timedOut = [bool]$result.TimedOut } } catch { }
        try { if ($result.PSObject.Properties.Name -contains "Success") { $success = [bool]$result.Success } } catch { }
        try { if ($result.PSObject.Properties.Name -contains "Added") { $added = [int]$result.Added } } catch { }
        try { if ($result.PSObject.Properties.Name -contains "Note") { $note = [string]$result.Note } } catch { }

        try { if ($result.PSObject.Properties.Name -contains "AddedTickets") { $addedTickets = @($result.AddedTickets) } } catch { }

        if ($timedOut -or (-not $success) -or $args.Error) {
            $script:TicketsSyncFailureCount = [int]$script:TicketsSyncFailureCount + 1
            $backoff = Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount
            $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds($backoff)
            Write-QOTicketsUILog ("Tickets: Background email sync failed. Next retry in {0}s. Reason: {1}" -f $backoff, $note) "WARN"
            Set-QOTicketsSyncStatus -StatusText $StatusText -Message ("Background sync retrying in {0}m" -f [math]::Ceiling($backoff / 60.0))
            return
        }

        $script:TicketsSyncFailureCount = 0
        $script:TicketsLastSuccessfulSyncUtc = (Get-Date).ToUniversalTime()
        $nextPollSeconds = Get-Random -Minimum 30 -Maximum 61
        $script:TicketsSyncNextAttemptUtc = $script:TicketsLastSuccessfulSyncUtc.AddSeconds($nextPollSeconds)

        $mergedCount = Merge-QOTicketsIntoGridCollection -Grid $Grid -IncomingTickets @($addedTickets)
        Write-QOTicketsUILog ("Tickets: Background email sync finished. Added=$added Merged=$mergedCount. Note=$note")
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message (("Last sync: {0}" -f (Get-Date).ToString("HH:mm:ss")))
    }

    $worker.RunWorkerAsync()
}

function Start-QOTicketsAutoSyncWorker {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [AllowNull()]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText
    )

    if ($script:TicketsSyncWorkerStarted) { return }
    $script:TicketsSyncWorkerStarted = $true

    if (-not $SyncCmd) {
        Write-QOTicketsUILog "Tickets: Sync command not available. Auto-sync disabled." "WARN"
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Tickets ready (sync unavailable)"
        return
    }

    $script:TicketsSyncNextAttemptUtc = [datetime]::MinValue
    Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Background sync scheduled"

    $script:TicketsSyncTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:TicketsSyncTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:TicketsSyncWorkerTickHandler = {
        if ($script:TicketsEmailSyncInProgress) { return }

        $nowUtc = (Get-Date).ToUniversalTime()
        if ($nowUtc -lt $script:TicketsSyncNextAttemptUtc) { return }

        Start-TicketsEmailSyncAsync -Grid $Grid -GetTicketsCmd $GetTicketsCmd -SyncCmd $SyncCmd -StatusText $StatusText
    }.GetNewClosure()

    $script:TicketsSyncTimer.Add_Tick($script:TicketsSyncWorkerTickHandler)
    $script:TicketsSyncTimer.Start()
}


function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [switch]$Force
    )

    Start-TicketsEmailSyncAsync -Grid $Grid -GetTicketsCmd $GetTicketsCmd -SyncCmd $SyncCmd -StatusText $StatusText
}

function Invoke-QOTicketsGridRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$View
    )

    Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd -View $View

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Grid.ItemsSource)
    if ($view) {
        $view.Refresh()
    }
}

function Initialize-QOTicketsUI {
    param([Parameter(Mandatory)]$Window)

    Add-Type -AssemblyName PresentationFramework | Out-Null

    # Capture core commands now
    $getTicketsCmd = $null
    try {
        $getTicketsCmd = Get-Command Get-QOTicketsByBucket -ErrorAction Stop
    } catch {
        try {
            $getTicketsCmd = Get-Command Get-QOTicketsByFolder -ErrorAction Stop
        } catch {
            $getTicketsCmd = Get-Command Get-QOTickets -ErrorAction Stop
        }
    }

    $newTicketCmd  = Get-Command New-QOTicket  -ErrorAction Stop
    $addTicketCmd  = Get-Command Add-QOTicket  -ErrorAction Stop
    $updateTicketCmd = Get-Command Update-QOTicket -ErrorAction Stop
    $removeCmd     = Get-Command Remove-QOTicket -ErrorAction Stop
    $restoreCmd    = Get-Command Restore-QOTickets -ErrorAction Stop
    $setStatusCmd  = Get-Command Set-QOTicketsStatus -ErrorAction Stop
    $renameTicketCmd = Get-Command Rename-QOTicket -ErrorAction Stop
    $sendReplyCmd = Get-Command Send-QOTicketReply -ErrorAction Stop
    $getStatusesCmd = Get-Command Get-QOTicketStatuses -ErrorAction Stop

    $syncCmd = $null
    try { $syncCmd = Get-Command Sync-QOTicketsFromEmail -ErrorAction Stop } catch { $syncCmd = $null }

    # Capture UI local function commands
    

    # Capture stable local references
    $grid       = $Window.FindName("TicketsGrid")
    $btnRefresh = $Window.FindName("BtnRefreshTickets")
    $btnNew     = $Window.FindName("BtnNewTicket")
    $btnDelete  = $Window.FindName("BtnDeleteTicket")
    $btnFilterMenu = $Window.FindName("BtnTicketsFilterMenu")

    $syncStatusText = $Window.FindName("TicketsSyncStatusText")
    $btnToggleDetails = $Window.FindName("BtnToggleTicketDetails")
    $detailsPanel = $Window.FindName("TicketDetailsPanel")
    $detailsChevron = $Window.FindName("TicketDetailsChevron")
    $ticketBodyText = $Window.FindName("TicketEmailBodyText")
    $ticketReplySubject = $Window.FindName("TicketReplySubject")
    $ticketReplyText = $Window.FindName("TicketReplyText")
    $btnSendReply = $Window.FindName("BtnSendTicketReply")

    if (-not $grid)       { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }
    if (-not $btnFilterMenu) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketsFilterMenu") | Out-Null; return }

    if (-not $syncStatusText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsSyncStatusText") | Out-Null; return }
    
    if (-not $btnToggleDetails) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnToggleTicketDetails") | Out-Null; return }
    if (-not $detailsPanel) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsPanel") | Out-Null; return }
    if (-not $detailsChevron) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsChevron") | Out-Null; return }
    if (-not $ticketBodyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketEmailBodyText") | Out-Null; return }
    if (-not $ticketReplySubject) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplySubject") | Out-Null; return }
    if (-not $ticketReplyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplyText") | Out-Null; return }
    if (-not $btnSendReply) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnSendTicketReply") | Out-Null; return }

    $script:TicketsGrid = $grid
    $script:TicketsSyncStatusText = $syncStatusText
    $script:TicketsEmailSyncInProgress = $false

    # Remove previous handlers safely (now that handlers are typed delegates, Remove_ should match)

    try { if ($script:TicketsRefreshHandler) { $btnRefresh.Remove_Click($script:TicketsRefreshHandler) } } catch { }
    try { if ($script:TicketsNewHandler)     { $btnNew.Remove_Click($script:TicketsNewHandler) } } catch { }
    try { if ($script:TicketsDeleteHandler)  { $btnDelete.Remove_Click($script:TicketsDeleteHandler) } } catch { }

    try { if ($script:TicketsToggleDetailsHandler) { $btnToggleDetails.Remove_Click($script:TicketsToggleDetailsHandler) } } catch { }
    try {
        if ($script:TicketsFilterCheckboxHandler) {
            foreach ($checkbox in @($script:TicketsFilterOpenCheckbox, $script:TicketsFilterClosedCheckbox, $script:TicketsFilterDeletedCheckbox)) {
                if (-not $checkbox) { continue }
                try { $checkbox.Remove_Click($script:TicketsFilterCheckboxHandler) } catch { }
            }
        }
    } catch { }
    try { if ($script:TicketsFilterButtonHandler) { $btnFilterMenu.Remove_Click($script:TicketsFilterButtonHandler) } } catch { }

    try {
        if ($script:TicketsSelectionChangedHandler) {
            $grid.RemoveHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:TicketsSelectionChangedHandler)
        }
    } catch { }

    try {
        if ($script:TicketsRowEditHandler) {
            $grid.Remove_RowEditEnding($script:TicketsRowEditHandler)
        }
    } catch { }

    try { if ($script:TicketsSendReplyHandler) { $btnSendReply.Remove_Click($script:TicketsSendReplyHandler) } } catch { }

    try {
        if ($script:TicketsContentRenderedHandler) {
            $Window.Remove_ContentRendered($script:TicketsContentRenderedHandler)
        }
    } catch { }

    try {
        if ($script:TicketsStatusContextMenuHandler) {
            $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseRightButtonDownEvent, $script:TicketsStatusContextMenuHandler)
        }
    } catch { }

    try {
        if ($script:TicketsSyncTimer) {
            if ($script:TicketsSyncWorkerTickHandler) {
                $script:TicketsSyncTimer.Remove_Tick($script:TicketsSyncWorkerTickHandler)
            }
            $script:TicketsSyncTimer.Stop()
            $script:TicketsSyncTimer = $null
        }
    } catch { }
    $script:TicketsSyncWorkerStarted = $false

    try {
        if ($script:TicketsFileRefreshTimer) {
            $script:TicketsFileRefreshTimer.Stop()
            $script:TicketsFileRefreshTimer = $null
        }
    } catch { }

    try {
        foreach ($evt in @($script:TicketsFileWatcherEvents)) {
            if ($evt) {
                Unregister-Event -SubscriptionId $evt.Id -ErrorAction SilentlyContinue
            }
        }
        $script:TicketsFileWatcherEvents = @()
    } catch { }

    try {
        if ($script:TicketsFileWatcher) {
            $script:TicketsFileWatcher.EnableRaisingEvents = $false
            $script:TicketsFileWatcher.Dispose()
            $script:TicketsFileWatcher = $null
        }
    } catch { }

    Update-QOTicketDetailsView -Ticket $null -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplySubject $ticketReplySubject -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron

    $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Extended

    if ($grid.ContextMenu) {
        $grid.ContextMenu = $null
    }
    $script:TicketsFilterMenu = New-Object System.Windows.Controls.ContextMenu
    $script:TicketsFilterMenu.StaysOpen = $true
    $btnFilterMenu.ContextMenu = $script:TicketsFilterMenu

    $filterState = Get-QOTicketsFilterState
    $script:ShowOpen = [bool]$filterState.ShowOpen
    $script:ShowClosed = [bool]$filterState.ShowClosed
    $script:ShowDeleted = [bool]$filterState.ShowDeleted

    $script:TicketsFilterOpenCheckbox = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterOpenCheckbox.Header = "Open"
    $script:TicketsFilterOpenCheckbox.IsCheckable = $true
    $script:TicketsFilterOpenCheckbox.IsChecked = [bool]$script:ShowOpen
    $script:TicketsFilterOpenCheckbox.IsEnabled = $true
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterOpenCheckbox) | Out-Null

    $script:TicketsFilterClosedCheckbox = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterClosedCheckbox.Header = "Closed"
    $script:TicketsFilterClosedCheckbox.IsCheckable = $true
    $script:TicketsFilterClosedCheckbox.IsChecked = [bool]$script:ShowClosed
    $script:TicketsFilterClosedCheckbox.IsEnabled = $true
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterClosedCheckbox) | Out-Null

    $script:TicketsFilterDeletedCheckbox = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterDeletedCheckbox.Header = "Deleted"
    $script:TicketsFilterDeletedCheckbox.IsCheckable = $true
    $script:TicketsFilterDeletedCheckbox.IsChecked = [bool]$script:ShowDeleted
    $script:TicketsFilterDeletedCheckbox.IsEnabled = $true
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterDeletedCheckbox) | Out-Null

    $updateFilterTooltip = {
        $labels = @()
        if ($script:ShowOpen) { $labels += "Open" }
        if ($script:ShowClosed) { $labels += "Closed" }
        if ($script:ShowDeleted) { $labels += "Deleted" }
        $summary = if ($labels.Count -gt 0) { $labels -join ", " } else { "None" }
        $btnFilterMenu.ToolTip = ("Filter tickets ({0})" -f $summary)
    }.GetNewClosure()

    $applyFilterSelection = {
        param([bool]$LogChange = $false)
        
        $script:ShowOpen = [bool]$script:TicketsFilterOpenCheckbox.IsChecked
        $script:ShowClosed = [bool]$script:TicketsFilterClosedCheckbox.IsChecked
        $script:ShowDeleted = [bool]$script:TicketsFilterDeletedCheckbox.IsChecked

        if (-not $script:TicketsFilterState) {
            $script:TicketsFilterState = [pscustomobject]@{
                ShowOpen    = [bool]$script:TicketsFilterDefaults.ShowOpen
                ShowClosed  = [bool]$script:TicketsFilterDefaults.ShowClosed
                ShowDeleted = [bool]$script:TicketsFilterDefaults.ShowDeleted
            }
        }

        foreach ($prop in @("ShowOpen", "ShowClosed", "ShowDeleted")) {
            if ($script:TicketsFilterState.PSObject.Properties.Name -notcontains $prop) {
                $script:TicketsFilterState | Add-Member -NotePropertyName $prop -NotePropertyValue ([bool]$script:TicketsFilterDefaults.$prop) -Force
            }
            if ($null -eq $script:TicketsFilterState.$prop) {
                $script:TicketsFilterState.$prop = [bool]$script:TicketsFilterDefaults.$prop
            }
        }

        $state = $script:TicketsFilterState
        $state.ShowOpen = $script:ShowOpen
        $state.ShowClosed = $script:ShowClosed
        $state.ShowDeleted = $script:ShowDeleted

        & $updateFilterTooltip

        if ($LogChange) {
            Write-QOTicketsFilterLog -Open $script:ShowOpen -Closed $script:ShowClosed -Deleted $script:ShowDeleted
        }
        Invoke-QOTicketsFilterSafely -ForceRefresh
    }.GetNewClosure()

    $script:TicketsFilterCheckboxHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
             & $applyFilterSelection $true
        } catch {
            Write-QOTicketsUILog ("Tickets: Filter change failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    foreach ($checkbox in @($script:TicketsFilterOpenCheckbox, $script:TicketsFilterClosedCheckbox, $script:TicketsFilterDeletedCheckbox)) {
        if (-not $checkbox) { continue }
        try { $checkbox.Add_Click($script:TicketsFilterCheckboxHandler) } catch { }
    }

    $script:TicketsFilterButtonHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $cm = $btnFilterMenu.ContextMenu
            if (-not $cm) { throw "FilterButton.ContextMenu is null" }
            if ($cm -is [System.Windows.Controls.ContextMenu]) {
                $cm.PlacementTarget = $btnFilterMenu
                $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
                $cm.IsOpen = $true
            } else {
                throw "Filter menu is not a ContextMenu"
            }
        } catch {
            Write-QOTicketsUILog ("Tickets: Filter menu open failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $btnFilterMenu.Add_Click($script:TicketsFilterButtonHandler)

    $script:TicketsRowContextMenu = New-Object System.Windows.Controls.ContextMenu
    $script:TicketsUndeleteMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsUndeleteMenuItem.Header = "Undelete"
    $script:TicketsRowContextMenu.Items.Add($script:TicketsUndeleteMenuItem) | Out-Null

    $script:TicketsUndeleteHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @($grid.SelectedItems)
            if ($selectedItems.Count -eq 0) { return }

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $null = & $restoreCmd -Id $ids
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        } catch {
            Write-QOTicketsUILog ("Tickets: Undelete failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $script:TicketsUndeleteMenuItem.Add_Click($script:TicketsUndeleteHandler)


    $script:TicketsStatusContextMenu = New-Object System.Windows.Controls.ContextMenu
    $statusMenuItems = @()
    try { $statusMenuItems = @(& $getStatusesCmd) } catch { $statusMenuItems = @("New", "In Progress", "Pending", "Closed") }

    foreach ($status in $statusMenuItems) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = $status
        $menuItem.Tag = $status
        $script:TicketsStatusContextMenu.Items.Add($menuItem) | Out-Null
    }
    $grid.ContextMenu = $script:TicketsStatusContextMenu

    # Menu item click handler must be typed RoutedEventHandler
    $script:TicketsStatusMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $statusValue = [string]$sender.Tag
            if ([string]::IsNullOrWhiteSpace($statusValue)) { return }

            $selectedItems = @($grid.SelectedItems)
            if ($selectedItems.Count -eq 0) { return }

            foreach ($item in $selectedItems) {
                if ($null -eq $item) { continue }
                if ($item.PSObject.Properties.Name -contains "Status") {
                    $item.Status = $statusValue
                }
            }
            $grid.Items.Refresh()

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $null = & $setStatusCmd -Id $ids -Status $statusValue
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        } catch {
            Write-QOTicketsUILog ("Tickets: Load handler failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    foreach ($menuItem in @($script:TicketsStatusContextMenu.Items)) {
        try { $menuItem.Add_Click($script:TicketsStatusMenuItemHandler) } catch { }
    }

    # Right click handler must be typed MouseButtonEventHandler
    $script:TicketsStatusContextMenuHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $args)
        try {
            $point = $args.GetPosition($grid)
            $hit = $grid.InputHitTest($point)
            if (-not $hit) { $args.Handled = $true; return }

            $cell = Get-QOParentVisual -Element $hit -Type ([System.Windows.Controls.DataGridCell])
            if (-not $cell) { $args.Handled = $true; return }
            if (-not $cell.Column) { $args.Handled = $true; return }

            $row = Get-QOParentVisual -Element $hit -Type ([System.Windows.Controls.DataGridRow])
            if (-not $row) { $args.Handled = $true; return }

            if (-not $row.IsSelected) {
                $grid.SelectedItems.Clear()
                $row.IsSelected = $true
                $grid.SelectedItem = $row.Item
            }


            $selectedItems = @($grid.SelectedItems)
            $hasDeleted = $false
            foreach ($item in $selectedItems) {
                if ($null -eq $item) { continue }
                try {
                    if ($item.PSObject.Properties.Name -contains "IsDeleted" -and [bool]$item.IsDeleted) {
                        $hasDeleted = $true
                        break
                    }
                } catch { }
            }

            if ($hasDeleted) {
                $script:TicketsUndeleteMenuItem.IsEnabled = ($selectedItems.Count -gt 0)
                $script:TicketsRowContextMenu.PlacementTarget = $cell
                $script:TicketsRowContextMenu.IsOpen = $true
                $args.Handled = $true
                return
            }

            if ($cell.Column.Header -eq "Status") {
                $script:TicketsStatusContextMenu.PlacementTarget = $cell
                $script:TicketsStatusContextMenu.IsOpen = $true
                $args.Handled = $true
                return
            }

            if ($cell.Column.Header -eq "Ticket Name") {
                $selectedItem = $grid.SelectedItem
                if (-not $selectedItem) { return }

                try { Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null } catch { }
                $currentName = ""
                try {
                    if ($selectedItem.PSObject.Properties.Name -contains "TicketName") {
                        $currentName = [string]$selectedItem.TicketName
                    } elseif ($selectedItem.PSObject.Properties.Name -contains "Title") {
                        $currentName = [string]$selectedItem.Title
                    }
                } catch { }

                $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Enter new ticket name:", "Rename ticket", $currentName)
                if ([string]::IsNullOrWhiteSpace($newName)) { return }

                try {
                    $idValue = [string]$selectedItem.Id
                    if ($idValue) {
                        $null = & $renameTicketCmd -Id $idValue -Name $newName
                        $selectedItem.TicketName = $newName
                        $selectedItem.Title = $newName
                        $grid.Items.Refresh()
                        Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
                    }
                } catch { }

                $args.Handled = $true
                return
            }
            $args.Handled = $true
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.UIElement]::PreviewMouseRightButtonDownEvent, $script:TicketsStatusContextMenuHandler)

    # ContentRendered handler: start background auto-sync worker after first render
    $script:TicketsContentRenderedHandler = [System.EventHandler]{
        param($sender, $args)
        try {
            Start-QOTicketsAutoSyncWorker -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusText $syncStatusText
        } catch { }
    }.GetNewClosure()
    $Window.Add_ContentRendered($script:TicketsContentRenderedHandler)

    # Refresh click handler typed (fast JSON refresh only)
    $script:TicketsRefreshHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
    }.GetNewClosure()
    $btnRefresh.Add_Click($script:TicketsRefreshHandler)

    # Toggle details click handler typed
    $script:TicketsToggleDetailsHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $isOpen = ($detailsPanel.Visibility -eq "Visible")
            if ($isOpen) {
                Set-QOTicketDetailsVisibility -DetailsPanel $detailsPanel -Chevron $detailsChevron -IsOpen:$false
            } else {
                Update-QOTicketDetailsView -Ticket $grid.SelectedItem -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplySubject $ticketReplySubject -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron
            }
        } catch { }
    }.GetNewClosure()
    $btnToggleDetails.Add_Click($script:TicketsToggleDetailsHandler)
    & $applyFilterSelection $false
    
    # Selection changed handler typed
    $script:TicketsSelectionChangedHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        param($sender, $args)
        try {
            Update-QOTicketDetailsView -Ticket $grid.SelectedItem -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplySubject $ticketReplySubject -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron
        } catch { }
    }.GetNewClosure()
    $grid.AddHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:TicketsSelectionChangedHandler)

    # Row edit handler typed
    $script:TicketsRowEditHandler = [System.Windows.Controls.DataGridRowEditEndingEventHandler]{
        param($sender, $args)
        try {
            if ($args.EditAction -ne [System.Windows.Controls.DataGridEditAction]::Commit) { return }

            $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
            $ticket = $args.Row.Item
            if ($null -eq $ticket) { return }

            $null = & $updateTicketCmd -Ticket $ticket
        } catch { }
    }.GetNewClosure()
    $grid.Add_RowEditEnding($script:TicketsRowEditHandler)

    # Send reply handler typed
    $script:TicketsSendReplyHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $ticket = $grid.SelectedItem
            if (-not $ticket) { return }

            $replySubject = ([string]$ticketReplySubject.Text).Trim()
            $replyText = ([string]$ticketReplyText.Text).Trim()
            if (-not $replySubject -or -not $replyText) {
                [System.Windows.MessageBox]::Show(
                    "Enter a subject and reply before sending.",
                    "Reply required",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
                return
            }

            $result = & $sendReplyCmd -Ticket $ticket -Subject $replySubject -Body $replyText
            $success = $false
            $note = ""
            try { $success = [bool]$result.Success } catch { $success = $false }
            try { if ($result.PSObject.Properties.Name -contains "Note") { $note = [string]$result.Note } } catch { }

            if ($success) {
                $ticketReplyText.Text = ""
                $ticketReplySubject.Text = ""
                Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView

            $null = & $updateTicketCmd -Ticket $ticket
            $ticketReplyText.Text = ""
            Write-QOTicketsUILog "Ticket reply saved to local history."

                [System.Windows.MessageBox]::Show(
                    "Reply sent.",
                    "Reply sent",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
            } else {
                [System.Windows.MessageBox]::Show(
                    ("Reply failed. " + $note),
                    "Reply failed",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
            }
        } catch {
            Write-QOTicketsUILog ("Ticket reply failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $btnSendReply.Add_Click($script:TicketsSendReplyHandler)

    # New ticket handler typed
    $script:TicketsNewHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $dialog = New-Object System.Windows.Window
            $dialog.Title = "New ticket"
            $dialog.Width = 420
            $dialog.Height = 320
            $dialog.WindowStartupLocation = "CenterOwner"
            $dialog.ResizeMode = "NoResize"
            $dialog.Owner = $Window

            $stack = New-Object System.Windows.Controls.StackPanel
            $stack.Margin = "12"

            $nameLabel = New-Object System.Windows.Controls.TextBlock
            $nameLabel.Text = "Ticket name"
            $nameLabel.Margin = "0,0,0,4"
            $stack.Children.Add($nameLabel) | Out-Null

            $nameBox = New-Object System.Windows.Controls.TextBox
            $nameBox.Margin = "0,0,0,8"
            $stack.Children.Add($nameBox) | Out-Null

            $statusLabel = New-Object System.Windows.Controls.TextBlock
            $statusLabel.Text = "Status"
            $statusLabel.Margin = "0,0,0,4"
            $stack.Children.Add($statusLabel) | Out-Null

            $statusBox = New-Object System.Windows.Controls.ComboBox
            $statusBox.Margin = "0,0,0,8"
            foreach ($status in @($statusMenuItems)) {
                $statusBox.Items.Add($status) | Out-Null
            }
            $statusBox.SelectedIndex = 0
            $stack.Children.Add($statusBox) | Out-Null

            $noteLabel = New-Object System.Windows.Controls.TextBlock
            $noteLabel.Text = "Initial note (optional)"
            $noteLabel.Margin = "0,0,0,4"
            $stack.Children.Add($noteLabel) | Out-Null

            $noteBox = New-Object System.Windows.Controls.TextBox
            $noteBox.Height = 90
            $noteBox.AcceptsReturn = $true
            $noteBox.TextWrapping = "Wrap"
            $noteBox.Margin = "0,0,0,12"
            $stack.Children.Add($noteBox) | Out-Null

            $buttonsPanel = New-Object System.Windows.Controls.StackPanel
            $buttonsPanel.Orientation = "Horizontal"
            $buttonsPanel.HorizontalAlignment = "Right"

            $btnCreate = New-Object System.Windows.Controls.Button
            $btnCreate.Content = "Create"
            $btnCreate.Width = 80
            $btnCreate.Margin = "0,0,8,0"
            $buttonsPanel.Children.Add($btnCreate) | Out-Null

            $btnCancel = New-Object System.Windows.Controls.Button
            $btnCancel.Content = "Cancel"
            $btnCancel.Width = 80
            $buttonsPanel.Children.Add($btnCancel) | Out-Null

            $stack.Children.Add($buttonsPanel) | Out-Null
            $dialog.Content = $stack

            $btnCancel.Add_Click({ $dialog.DialogResult = $false })
            $btnCreate.Add_Click({ $dialog.DialogResult = $true })

            $result = $dialog.ShowDialog()
            if (-not $result) { return }

            $ticketName = ([string]$nameBox.Text).Trim()
            if (-not $ticketName) {
                [System.Windows.MessageBox]::Show(
                    "Ticket name is required.",
                    "Validation",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }

            $statusValue = "New"
            if ($statusBox.SelectedItem) {
                $statusValue = [string]$statusBox.SelectedItem
            }

            $initialNote = ([string]$noteBox.Text).Trim()

            $ticket = & $newTicketCmd -Title $ticketName -TicketName $ticketName -Subject $ticketName -Status $statusValue -InitialNote $initialNote
            $null   = & $addTicketCmd -Ticket $ticket

            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView

            $grid.SelectedItem = $ticket
            $grid.ScrollIntoView($ticket)

            if ($grid.Columns.Count -gt 0) {
                $grid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo($ticket, $grid.Columns[0])
                $grid.BeginEdit()
            }
        }
        catch {
            Write-QOTicketsUILog ("Create ticket failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $btnNew.Add_Click($script:TicketsNewHandler)

    # Delete handler typed
    $script:TicketsDeleteHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @($grid.SelectedItems)
            if ($selectedItems.Count -eq 0) { return }

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $confirmText = if ($ids.Count -gt 1) {
                "Delete {0} tickets?" -f $ids.Count
            } else {
                "Delete this ticket?"
            }

            $confirm = [System.Windows.MessageBox]::Show($confirmText, "Confirm", "YesNo", "Warning")
            if ($confirm -ne "Yes") { return }

            $null = & $removeCmd -Id $ids
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        }
        catch { }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)


    Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
    Set-QOTicketsSyncStatus -StatusText $syncStatusText -Message "Tickets ready"
}

Export-ModuleMember -Function Write-QOTicketsUILog, Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh, Start-TicketsEmailSyncAsync
