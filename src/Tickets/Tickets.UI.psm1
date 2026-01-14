# src\Tickets\Tickets.UI.psm1
# UI wiring for Tickets tab (NO core logic in here)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\Core\Logging\Logging.psm1") -Force -ErrorAction SilentlyContinue

# -------------------------
# State
# -------------------------
$script:TicketsGrid = $null
$script:TicketsEmailSyncRan = $false

# Stored handlers to avoid double wiring
$script:TicketsLoadedHandler  = $null
$script:TicketsRefreshHandler = $null
$script:TicketsNewHandler     = $null
$script:TicketsDeleteHandler  = $null
$script:TicketsRestoreHandler = $null
$script:TicketsDeletedToggleHandler = $null
$script:TicketsToggleDetailsHandler = $null
$script:TicketsSelectionChangedHandler = $null
$script:TicketsRowEditHandler = $null
$script:TicketsSendReplyHandler = $null

$script:TicketsAutoRefreshTimer = $null
$script:TicketsAutoRefreshInProgress = $false
$script:TicketsFileWatcher = $null
$script:TicketsFileWatcherEvents = @()
$script:TicketsFileRefreshTimer = $null
$script:TicketsCurrentFolder = "Active"

function Write-QOTicketsUILog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = "INFO"
    )
    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
        }
    } catch { }
}

Write-QOTicketsUILog "=== Tickets.UI.psm1 LOADED ==="

function Get-QOTicketsForGrid {
    param(
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$Folder
    )

    try {
        $supportsFolder = $false
        try {
            $supportsFolder = ($GetTicketsCmd.Parameters.Keys -contains "Folder")
        } catch { }
        if ($supportsFolder) {
            $items = & $GetTicketsCmd -Folder $Folder
        } else {
            $items = & $GetTicketsCmd
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
        return @()
    }
}

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$Folder
    )

    try {
        $items = @(Get-QOTicketsForGrid -GetTicketsCmd $GetTicketsCmd -Folder $Folder)
        $Grid.ItemsSource = $items
        $Grid.Items.Refresh()

        $sourceType = $null
        try { $sourceType = $Grid.ItemsSource.GetType().FullName } catch { }

        $gridCount = 0
        try { $gridCount = $Grid.Items.Count } catch { }

        Write-QOTicketsUILog ("Tickets: ItemsSource set. Type={0}; Items={1}; GridCount={2}" -f $sourceType, $items.Count, $gridCount)
    }
    catch {
        [System.Windows.MessageBox]::Show("Load tickets failed.`r`n$($_.Exception.Message)") | Out-Null
    }
}

function Update-QOTicketsFolderState {
    param(
        [AllowNull()][System.Windows.Controls.Primitives.ToggleButton]$ToggleButton,
        [AllowNull()][System.Windows.Controls.Button]$DeleteButton,
        [AllowNull()][System.Windows.Controls.Button]$RestoreButton
    )

   if (-not $ToggleButton) { return }
    $script:TicketsCurrentFolder = if ($ToggleButton.IsChecked -eq $true) { "Deleted" } else { "Active" }

    if ($DeleteButton) {
        $DeleteButton.IsEnabled = ($script:TicketsCurrentFolder -ne "Deleted")
    }
    if ($RestoreButton) {
        $RestoreButton.IsEnabled = ($script:TicketsCurrentFolder -eq "Deleted")
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
        [AllowNull()][System.Windows.Controls.TextBox]$ReplyText,
        [AllowNull()][System.Windows.Controls.Button]$ReplyButton,
        [AllowNull()][System.Windows.Controls.TextBlock]$Chevron
    )

    if (-not $Ticket) {
        if ($BodyText) { $BodyText.Text = "Select a ticket to view details." }
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
    if ($ReplyButton) { $ReplyButton.IsEnabled = $true }
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

function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [string]$Folder
    )

    Write-QOTicketsUILog "Tickets: Email sync started"

    try {
        if ($SyncCmd) {
            $result = & $SyncCmd

            $note  = ""
            $added = 0
            try { if ($result -and ($result.PSObject.Properties.Name -contains "Note"))  { $note  = [string]$result.Note } } catch { }
            try { if ($result -and ($result.PSObject.Properties.Name -contains "Added")) { $added = [int]$result.Added } } catch { }

            Write-QOTicketsUILog ("Tickets: Email sync finished. Added=$added. Note=$note")
        } else {
            Write-QOTicketsUILog "Tickets: Sync command not available (skipping)" "WARN"
        }
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Email sync failed: " + $_.Exception.Message) "ERROR"
    }

    Invoke-QOTicketsGridRefresh -Grid $Grid -GetTicketsCmd $GetTicketsCmd -Folder $Folder
}

function Invoke-QOTicketsGridRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$Folder
    )

    Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd -Folder $Folder

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
        $getTicketsCmd = Get-Command Get-QOTicketsByFolder -ErrorAction Stop
    } catch {
        $getTicketsCmd = Get-Command Get-QOTickets -ErrorAction Stop
    }

    $newTicketCmd  = Get-Command New-QOTicket  -ErrorAction Stop
    $addTicketCmd  = Get-Command Add-QOTicket  -ErrorAction Stop
    $updateTicketCmd = Get-Command Update-QOTicket -ErrorAction Stop
    $removeCmd     = Get-Command Remove-QOTicket -ErrorAction Stop
    $restoreCmd    = Get-Command Restore-QOTickets -ErrorAction Stop
    $setStatusCmd  = Get-Command Set-QOTicketsStatus -ErrorAction Stop

    $syncCmd = $null
    try { $syncCmd = Get-Command Sync-QOTicketsFromEmail -ErrorAction Stop } catch { $syncCmd = $null }

    # Capture UI local function commands
    $emailSyncAndRefreshCmd = Get-Command Invoke-QOTicketsEmailSyncAndRefresh -ErrorAction Stop

    # Capture stable local references
    $grid       = $Window.FindName("TicketsGrid")
    $btnRefresh = $Window.FindName("BtnRefreshTickets")
    $btnNew     = $Window.FindName("BtnNewTicket")
    $btnDelete  = $Window.FindName("BtnDeleteTicket")
    $btnToggleDeleted = $Window.FindName("BtnToggleDeletedView")
    $btnRestore = $Window.FindName("BtnRestoreTicketToolbar")
    $btnToggleDetails = $Window.FindName("BtnToggleTicketDetails")
    $detailsPanel = $Window.FindName("TicketDetailsPanel")
    $detailsChevron = $Window.FindName("TicketDetailsChevron")
    $ticketBodyText = $Window.FindName("TicketEmailBodyText")
    $ticketReplyText = $Window.FindName("TicketReplyText")
    $btnSendReply = $Window.FindName("BtnSendTicketReply")

    if (-not $grid)       { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }
    if (-not $btnToggleDeleted) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnToggleDeletedView") | Out-Null; return }
    if (-not $btnRestore) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRestoreTicketToolbar") | Out-Null; return }
   
    if (-not $btnToggleDetails) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnToggleTicketDetails") | Out-Null; return }
    if (-not $detailsPanel) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsPanel") | Out-Null; return }
    if (-not $detailsChevron) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsChevron") | Out-Null; return }
    if (-not $ticketBodyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketEmailBodyText") | Out-Null; return }
    if (-not $ticketReplyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplyText") | Out-Null; return }
    if (-not $btnSendReply) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnSendTicketReply") | Out-Null; return }

    $script:TicketsGrid = $grid

    # Remove previous handlers safely (now that handlers are typed delegates, Remove_ should match)
    try {
        if ($script:TicketsLoadedHandler) {
            $grid.RemoveHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)
        }
    } catch { }

    try { if ($script:TicketsRefreshHandler) { $btnRefresh.Remove_Click($script:TicketsRefreshHandler) } } catch { }
    try { if ($script:TicketsNewHandler)     { $btnNew.Remove_Click($script:TicketsNewHandler) } } catch { }
    try { if ($script:TicketsDeleteHandler)  { $btnDelete.Remove_Click($script:TicketsDeleteHandler) } } catch { }
    try { if ($script:TicketsRestoreHandler) { $btnRestore.Remove_Click($script:TicketsRestoreHandler) } } catch { }

    try { if ($script:TicketsToggleDetailsHandler) { $btnToggleDetails.Remove_Click($script:TicketsToggleDetailsHandler) } } catch { }
    try { if ($script:TicketsDeletedToggleHandler) { $btnToggleDeleted.Remove_Click($script:TicketsDeletedToggleHandler) } } catch { }

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
        if ($script:TicketsStatusContextMenuHandler) {
            $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseRightButtonDownEvent, $script:TicketsStatusContextMenuHandler)
        }
    } catch { }

    try {
        if ($script:TicketsAutoRefreshTimer) {
            $script:TicketsAutoRefreshTimer.Stop()
            $script:TicketsAutoRefreshTimer = $null
        }
    } catch { }

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

    Update-QOTicketDetailsView -Ticket $null -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron

    $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Extended

    if ($grid.ContextMenu) {
        $grid.ContextMenu = $null
    }

    $script:TicketsStatusContextMenu = New-Object System.Windows.Controls.ContextMenu
    $statusMenuItems = @()
    $statusMenuItems = @("New", "In Progress", "Waiting on User", "No Longer Required", "Completed")

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
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -Folder $script:TicketsCurrentFolder
        } catch { }
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
            if ($cell.Column -and $cell.Column.Header -ne "Status") { $args.Handled = $true; return }

            $row = Get-QOParentVisual -Element $hit -Type ([System.Windows.Controls.DataGridRow])
            if (-not $row) { $args.Handled = $true; return }

            if (-not $row.IsSelected) {
                $grid.SelectedItems.Clear()
                $row.IsSelected = $true
                $grid.SelectedItem = $row.Item
            }

            $script:TicketsStatusContextMenu.PlacementTarget = $cell
            $script:TicketsStatusContextMenu.IsOpen = $true
            $args.Handled = $true
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.UIElement]::PreviewMouseRightButtonDownEvent, $script:TicketsStatusContextMenuHandler)

    # Loaded handler must be typed RoutedEventHandler
    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                 & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -Folder $script:TicketsCurrentFolder
            } else {
                Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -Folder $script:TicketsCurrentFolder
            }
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)

    # Refresh click handler typed
    $script:TicketsRefreshHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -Folder $script:TicketsCurrentFolder
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
                Update-QOTicketDetailsView -Ticket $grid.SelectedItem -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron
            }
        } catch { }
    }.GetNewClosure()
    $btnToggleDetails.Add_Click($script:TicketsToggleDetailsHandler)

    $script:TicketsDeletedToggleHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            Update-QOTicketsFolderState -ToggleButton $btnToggleDeleted -DeleteButton $btnDelete -RestoreButton $btnRestore
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -Folder $script:TicketsCurrentFolder
        } catch { }
    }.GetNewClosure()
    $btnToggleDeleted.Add_Click($script:TicketsDeletedToggleHandler)
    
    # Selection changed handler typed
    $script:TicketsSelectionChangedHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        param($sender, $args)
        try {
            Update-QOTicketDetailsView -Ticket $grid.SelectedItem -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron
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

            $replyText = ([string]$ticketReplyText.Text).Trim()
            if (-not $replyText) {
                [System.Windows.MessageBox]::Show(
                    "Enter a reply before sending.",
                    "Reply required",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
                return
            }

            $replyEntry = [pscustomobject]@{
                Body      = $replyText
                CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }

            $existingReplies = @()
            try {
                if ($ticket.PSObject.Properties.Name -contains "Replies") {
                    $existingReplies = @($ticket.Replies)
                }
            } catch { $existingReplies = @() }

            $ticket.Replies = @($existingReplies) + @($replyEntry)

            $null = & $updateTicketCmd -Ticket $ticket
            $ticketReplyText.Text = ""
            Write-QOTicketsUILog "Ticket reply saved to local history."

            [System.Windows.MessageBox]::Show(
                "Reply saved to ticket history (email sending not wired yet).",
                "Reply saved",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        } catch {
            Write-QOTicketsUILog ("Ticket reply failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $btnSendReply.Add_Click($script:TicketsSendReplyHandler)

    # New ticket handler typed
    $script:TicketsNewHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $ticket = & $newTicketCmd -Title "New ticket"
            $null   = & $addTicketCmd -Ticket $ticket

            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -Folder $script:TicketsCurrentFolder

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
            & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -Folder $script:TicketsCurrentFolder
        }
        catch { }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)

    # Restore handler typed
    $script:TicketsRestoreHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @($grid.SelectedItems)
            if ($selectedItems.Count -eq 0) { return }

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ($_.Folder -eq "Deleted") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $null = & $restoreCmd -Id $ids
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -Folder $script:TicketsCurrentFolder
        }
        catch { }
    }.GetNewClosure()
    $btnRestore.Add_Click($script:TicketsRestoreHandler)


    if ($syncCmd) {
        $script:TicketsAutoRefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:TicketsAutoRefreshTimer.Interval = [TimeSpan]::FromSeconds(60)
        $script:TicketsAutoRefreshTimer.Add_Tick({
            if ($script:TicketsAutoRefreshInProgress) { return }
            $script:TicketsAutoRefreshInProgress = $true
            try {
                if (-not $grid.IsLoaded) { return }
                & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -Folder $script:TicketsCurrentFolder
            } catch { }
            finally {
                $script:TicketsAutoRefreshInProgress = $false
            }
        })
        $script:TicketsAutoRefreshTimer.Start()
    }

    Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -Folder $script:TicketsCurrentFolder
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
