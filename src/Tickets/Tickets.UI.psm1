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
$script:TicketsToggleDetailsHandler = $null
$script:TicketsSelectionChangedHandler = $null
$script:TicketsRowEditHandler = $null
$script:TicketsSendReplyHandler = $null
$script:TicketsFilterMenuHandler = $null
$script:TicketsFilterButtonHandler = $null
$script:TicketsUndeleteHandler = $null

$script:TicketsAutoRefreshTimer = $null
$script:TicketsAutoRefreshInProgress = $false
$script:TicketsFileWatcher = $null
$script:TicketsFileWatcherEvents = @()
$script:TicketsFileRefreshTimer = $null
$script:TicketsCurrentView = "Open"

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


function New-QOTicketsObservableCollection {
    param([object[]]$Items)

    $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($item in @($Items)) {
        $collection.Add($item) | Out-Null
    }
    return $collection
}

function Get-QOTicketsForGrid {
    param(
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$View
    )

    try {
        $storePath = ""
        try { $storePath = Get-QOTicketsStorePath } catch { $storePath = "" }
        Write-QOTicketsUILog ("Tickets: Load start. View={0}; StorePath={1}" -f $View, $storePath)
        $supportsFolder = $false
        $supportsBucket = $false
        try {
            $supportsFolder = ($GetTicketsCmd.Parameters.Keys -contains "Folder")
            $supportsBucket = ($GetTicketsCmd.Parameters.Keys -contains "Bucket")
        } catch { }
        if ($supportsBucket) {
            $items = & $GetTicketsCmd -Bucket $View
        } elseif ($supportsFolder) {
            $folderValue = if ($View -eq "Deleted") { "Deleted" } else { "Active" }
            $items = & $GetTicketsCmd -Folder $folderValue
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

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$View
    )

    try {
        Write-QOTicketsUILog ("Tickets: Grid refresh started. View={0}" -f $View)
        $items = @(Get-QOTicketsForGrid -GetTicketsCmd $GetTicketsCmd -View $View)
        $Grid.ItemsSource = (New-QOTicketsObservableCollection -Items $items)
        $Grid.Items.Refresh()

        $sourceType = $null
        try { $sourceType = $Grid.ItemsSource.GetType().FullName } catch { }

        $gridCount = 0
        try { $gridCount = $Grid.Items.Count } catch { }

        Write-QOTicketsUILog ("Tickets: ItemsSource set. Type={0}; Items={1}; GridCount={2}" -f $sourceType, $items.Count, $gridCount)
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

function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [string]$View
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

    Invoke-QOTicketsGridRefresh -Grid $Grid -GetTicketsCmd $GetTicketsCmd -View $View
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
    $emailSyncAndRefreshCmd = Get-Command Invoke-QOTicketsEmailSyncAndRefresh -ErrorAction Stop

    # Capture stable local references
    $grid       = $Window.FindName("TicketsGrid")
    $btnRefresh = $Window.FindName("BtnRefreshTickets")
    $btnNew     = $Window.FindName("BtnNewTicket")
    $btnDelete  = $Window.FindName("BtnDeleteTicket")
    $btnFilterMenu = $Window.FindName("BtnTicketsFilterMenu")
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
   
    if (-not $btnToggleDetails) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnToggleTicketDetails") | Out-Null; return }
    if (-not $detailsPanel) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsPanel") | Out-Null; return }
    if (-not $detailsChevron) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsChevron") | Out-Null; return }
    if (-not $ticketBodyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketEmailBodyText") | Out-Null; return }
    if (-not $ticketReplySubject) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplySubject") | Out-Null; return }
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

    try { if ($script:TicketsToggleDetailsHandler) { $btnToggleDetails.Remove_Click($script:TicketsToggleDetailsHandler) } } catch { }
    try {
        if ($script:TicketsFilterMenuHandler -and $script:TicketsFilterMenu) {
            foreach ($menuItem in @($script:TicketsFilterMenu.Items)) {
                try { $menuItem.Remove_Click($script:TicketsFilterMenuHandler) } catch { }
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

    Update-QOTicketDetailsView -Ticket $null -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplySubject $ticketReplySubject -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron

    $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Extended

    if ($grid.ContextMenu) {
        $grid.ContextMenu = $null
    }
    $script:TicketsFilterMenu = New-Object System.Windows.Controls.ContextMenu
    foreach ($viewName in @("Open", "Closed", "Deleted", "All")) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = $viewName
        $menuItem.Tag = $viewName
        $script:TicketsFilterMenu.Items.Add($menuItem) | Out-Null
    }

    $setTicketsView = {
        param([string]$ViewName)
        $viewValue = if ([string]::IsNullOrWhiteSpace($ViewName)) { "Open" } else { $ViewName }
        $script:TicketsCurrentView = $viewValue
        $btnDelete.IsEnabled = ($viewValue -ne "Deleted")
        $btnFilterMenu.ToolTip = ("Filter tickets ({0})" -f $viewValue)
        foreach ($menuItem in @($script:TicketsFilterMenu.Items)) {
            try { $menuItem.IsChecked = ($menuItem.Tag -eq $viewValue) } catch { }
        }
        Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
    }.GetNewClosure()

    $script:TicketsFilterMenuHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $viewValue = [string]$sender.Tag
            & $setTicketsView $viewValue
        } catch {
            Write-QOTicketsUILog ("Tickets: Filter change failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    foreach ($menuItem in @($script:TicketsFilterMenu.Items)) {
        try { $menuItem.Add_Click($script:TicketsFilterMenuHandler) } catch { }
    }

    $script:TicketsFilterButtonHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $script:TicketsFilterMenu.PlacementTarget = $btnFilterMenu
            $script:TicketsFilterMenu.IsOpen = $true
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


            if ($script:TicketsCurrentView -eq "Deleted") {
                $script:TicketsUndeleteMenuItem.IsEnabled = ($grid.SelectedItems.Count -gt 0)
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

    # Loaded handler must be typed RoutedEventHandler
    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                 & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -View $script:TicketsCurrentView
            } else {
                Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
            }
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)

    # Refresh click handler typed
    $script:TicketsRefreshHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -View $script:TicketsCurrentView
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
    & $setTicketsView "Open"
    
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
            & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -View $script:TicketsCurrentView
        }
        catch { }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)

    if ($syncCmd) {
        $script:TicketsAutoRefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:TicketsAutoRefreshTimer.Interval = [TimeSpan]::FromSeconds(60)
        $script:TicketsAutoRefreshTimer.Add_Tick({
            if ($script:TicketsAutoRefreshInProgress) { return }
            $script:TicketsAutoRefreshInProgress = $true
            try {
                if (-not $grid.IsLoaded) { return }
                & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -View $script:TicketsCurrentView
            } catch { }
            finally {
                $script:TicketsAutoRefreshInProgress = $false
            }
        })
        $script:TicketsAutoRefreshTimer.Start()
    }

    Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
