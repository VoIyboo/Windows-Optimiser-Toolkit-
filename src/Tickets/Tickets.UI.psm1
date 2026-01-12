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
$script:TicketsStatusHandler  = $null
$script:TicketsRestoreHandler = $null
$script:TicketsFilterChangeHandler = $null
$script:TicketsFilterSelectAllHandler = $null
$script:TicketsFilterClearAllHandler = $null
$script:TicketsFilterToggleHandler = $null
$script:TicketsFilterPopupKeyHandler = $null
$script:TicketsToggleDetailsHandler = $null
$script:TicketsSelectionChangedHandler = $null
$script:TicketsRowEditHandler = $null
$script:TicketsSendReplyHandler = $null
$script:TicketsStatusContextMenuHandler = $null
$script:TicketsStatusMenuItemHandler = $null
$script:TicketsStatusContextMenu = $null

$script:TicketFilterStatusBoxes = $null
$script:TicketFilterIncludeDeleted = $null
$script:TicketFilterActiveDot = $null
$script:TicketFilterPopup = $null
$script:TicketsAutoRefreshTimer = $null
$script:TicketsAutoRefreshInProgress = $false
$script:TicketsFileWatcher = $null
$script:TicketsFileWatcherEvents = @()
$script:TicketsFileRefreshTimer = $null
$script:TicketFilterStatusKeyMap = @{
    "New" = "New"
    "In Progress" = "InProgress"
    "Waiting on User" = "WaitingOnUser"
    "No Longer Required" = "NoLongerRequired"
    "Completed" = "Completed"
}


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
        [string[]]$Statuses,
        [bool]$IncludeDeleted
    )

    try {
        if ($GetTicketsCmd.Parameters.Keys -contains "Status") {
            $items = & $GetTicketsCmd -Status $Statuses -IncludeDeleted:$IncludeDeleted
        } else {
            $items = & $GetTicketsCmd
        }
        if ($null -eq $items) { return @() }
        return @($items)
    }
    catch {
        return @()
    }
}

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string[]]$Statuses,
        [bool]$IncludeDeleted
    )

    try {
        $items = @(Get-QOTicketsForGrid -GetTicketsCmd $GetTicketsCmd -Statuses $Statuses -IncludeDeleted:$IncludeDeleted)
        $Grid.ItemsSource = $items
        $Grid.Items.Refresh()
    }
    catch {
        [System.Windows.MessageBox]::Show("Load tickets failed.`r`n$($_.Exception.Message)") | Out-Null
    }
}

function Get-QOTicketFilterState {
    param(
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $statuses = $null
    if ($StatusBoxes) {
        $statuses = @(
            $StatusBoxes.GetEnumerator() |
                Where-Object { $_.Value -and $_.Value.IsChecked } |
                ForEach-Object { $_.Key }
        )
    }

    $includeDeleted = $false
    try { $includeDeleted = ($IncludeDeletedBox.IsChecked -eq $true) } catch { }

    return [pscustomobject]@{
        Statuses = $statuses
        IncludeDeleted = $includeDeleted
    }
}

function Update-QOTicketFilterIndicator {
    param(
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox,
        [AllowNull()][System.Windows.UIElement]$Indicator
    )
    if (-not $Indicator) { return }

    $allSelected = $true
    if ($StatusBoxes) {
        foreach ($box in $StatusBoxes.Values) {
            if (-not $box.IsChecked) {
                $allSelected = $false
                break
            }
        }
    }

    $includeDeleted = $false
    try { $includeDeleted = ($IncludeDeletedBox.IsChecked -eq $true) } catch { }

    $indicatorActive = (-not $allSelected) -or $includeDeleted
    $Indicator.Visibility = if ($indicatorActive) { "Visible" } else { "Collapsed" }
}

function Get-QOTicketFilterSettings {
    $settings = Get-QOSettings
    if (-not $settings.Tickets) {
        $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $settings.Tickets.StatusFilters) {
        $settings.Tickets | Add-Member -NotePropertyName StatusFilters -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    return $settings.Tickets.StatusFilters
}

function Save-QOTicketFilterSettings {
    param(
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $settings = Get-QOSettings
    if (-not $settings.Tickets) {
        $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $settings.Tickets.StatusFilters) {
        $settings.Tickets | Add-Member -NotePropertyName StatusFilters -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    foreach ($status in $StatusBoxes.Keys) {
        $settingKey = $script:TicketFilterStatusKeyMap[$status]
        if (-not $settingKey) { continue }
        $isChecked = $false
        try { $isChecked = ($StatusBoxes[$status].IsChecked -eq $true) } catch { }
        if ($settings.Tickets.StatusFilters.PSObject.Properties.Name -notcontains $settingKey) {
            $settings.Tickets.StatusFilters | Add-Member -NotePropertyName $settingKey -NotePropertyValue $isChecked -Force
        } else {
            $settings.Tickets.StatusFilters.$settingKey = $isChecked
        }
    }

    $includeDeleted = $false
    try { $includeDeleted = ($IncludeDeletedBox.IsChecked -eq $true) } catch { }
    if ($settings.Tickets.StatusFilters.PSObject.Properties.Name -notcontains "IncludeDeleted") {
        $settings.Tickets.StatusFilters | Add-Member -NotePropertyName IncludeDeleted -NotePropertyValue $includeDeleted -Force
    } else {
        $settings.Tickets.StatusFilters.IncludeDeleted = $includeDeleted
    }

    Save-QOSettings -Settings $settings
}

function Set-QOTicketFilterFromSettings {
    param(
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $filters = Get-QOTicketFilterSettings

    foreach ($status in $StatusBoxes.Keys) {
        $settingKey = $script:TicketFilterStatusKeyMap[$status]
        if (-not $settingKey) { continue }
        $value = $true
        try {
            if ($filters.PSObject.Properties.Name -contains $settingKey) {
                $value = [bool]$filters.$settingKey
            }
        } catch { }
        $StatusBoxes[$status].IsChecked = $value
    }

    $includeDeleted = $false
    try {
        if ($filters.PSObject.Properties.Name -contains "IncludeDeleted") {
            $includeDeleted = [bool]$filters.IncludeDeleted
        }
    } catch { }
    if ($IncludeDeletedBox) {
        $IncludeDeletedBox.IsChecked = $includeDeleted
    }
}

function Set-QOTicketsGridFilter {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Grid.ItemsSource)
    if (-not $view) { return }

    $view.Filter = {
        param($item)
        if (-not $item) { return $false }

        $filterState = Get-QOTicketFilterState -StatusBoxes $StatusBoxes -IncludeDeletedBox $IncludeDeletedBox
        if (-not $filterState.Statuses -or $filterState.Statuses.Count -eq 0) {
            return $false
        }

        $statusValue = $null
        try {
            if ($item.PSObject.Properties.Name -contains "Status") {
                $statusValue = [string]$item.Status
            }
        } catch { }

        if (-not $statusValue) { return $false }

        $isDeleted = $false
        try {
            if ($item.PSObject.Properties.Name -contains "IsDeleted") {
                $isDeleted = [bool]$item.IsDeleted
            } elseif ($item.PSObject.Properties.Name -contains "Folder") {
                $isDeleted = ([string]$item.Folder -eq "Deleted")
            }
        } catch { }

        if (-not $filterState.IncludeDeleted -and $isDeleted) {
            return $false
        }

        return ($filterState.Statuses -contains $statusValue)
    }.GetNewClosure()
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
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox
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

    Invoke-QOTicketsGridRefresh -Grid $Grid -GetTicketsCmd $GetTicketsCmd -StatusBoxes $StatusBoxes -IncludeDeletedBox $IncludeDeletedBox
}

function Invoke-QOTicketsGridRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [AllowNull()][hashtable]$StatusBoxes,
        [AllowNull()][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $filterState = Get-QOTicketFilterState -StatusBoxes $StatusBoxes -IncludeDeletedBox $IncludeDeletedBox
    Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd -Statuses $filterState.Statuses -IncludeDeleted:$filterState.IncludeDeleted
    Set-QOTicketsGridFilter -Grid $Grid -StatusBoxes $StatusBoxes -IncludeDeletedBox $IncludeDeletedBox
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Grid.ItemsSource)
    if ($view) {
        $view.Refresh()
    }
}

function Initialize-QOTicketsUI {
    param([Parameter(Mandatory)]$Window)

    Add-Type -AssemblyName PresentationFramework | Out-Null

    # Capture core commands now
    $getTicketsCmd = Get-Command Get-QOTickets -ErrorAction Stop
    $newTicketCmd  = Get-Command New-QOTicket  -ErrorAction Stop
    $addTicketCmd  = Get-Command Add-QOTicket  -ErrorAction Stop
    $updateTicketCmd = Get-Command Update-QOTicket -ErrorAction Stop
    $removeCmd     = Get-Command Remove-QOTicket -ErrorAction Stop
    $setStatusCmd  = Get-Command Set-QOTicketsStatus -ErrorAction Stop
    $getStatusesCmd = Get-Command Get-QOTicketStatuses -ErrorAction Stop
    $restoreCmd    = Get-Command Restore-QOTickets -ErrorAction Stop

    $syncCmd = $null
    try { $syncCmd = Get-Command Sync-QOTicketsFromEmail -ErrorAction Stop } catch { $syncCmd = $null }

    # Capture UI local function commands
    $emailSyncAndRefreshCmd = Get-Command Invoke-QOTicketsEmailSyncAndRefresh -ErrorAction Stop

    # Capture stable local references
    $grid       = $Window.FindName("TicketsGrid")
    $btnRefresh = $Window.FindName("BtnRefreshTickets")
    $btnNew     = $Window.FindName("BtnNewTicket")
    $btnDelete  = $Window.FindName("BtnDeleteTicket")
    $btnRestore = $Window.FindName("BtnRestoreTicketToolbar")
    $btnFilterToggle = $Window.FindName("BtnTicketFilter")
    $filterPopup = $Window.FindName("TicketFilterPopup")
    $filterPopupPanel = $Window.FindName("TicketFilterPopupPanel")
    $filterActiveDot = $Window.FindName("TicketFilterActiveDot")
    $btnToggleDetails = $Window.FindName("BtnToggleTicketDetails")
    $detailsPanel = $Window.FindName("TicketDetailsPanel")
    $detailsChevron = $Window.FindName("TicketDetailsChevron")
    $ticketBodyText = $Window.FindName("TicketEmailBodyText")
    $ticketReplyText = $Window.FindName("TicketReplyText")
    $btnSendReply = $Window.FindName("BtnSendTicketReply")
    $statusSelector = $Window.FindName("TicketStatusSelector")
    $btnSetStatus = $Window.FindName("BtnSetTicketStatus")    
    $filterStatusNew = $Window.FindName("TicketFilterStatusNew")
    $filterStatusInProgress = $Window.FindName("TicketFilterStatusInProgress")
    $filterStatusWaitingOnUser = $Window.FindName("TicketFilterStatusWaitingOnUser")
    $filterStatusNoLongerRequired = $Window.FindName("TicketFilterStatusNoLongerRequired")
    $filterStatusCompleted = $Window.FindName("TicketFilterStatusCompleted")
    $filterIncludeDeleted = $Window.FindName("TicketFilterIncludeDeleted")
    $btnFilterSelectAll = $Window.FindName("BtnTicketFilterSelectAllStatuses")
    $btnFilterClearAll = $Window.FindName("BtnTicketFilterClearAllStatuses")
    
    if (-not $grid)       { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }
    if (-not $btnRestore) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRestoreTicketToolbar") | Out-Null; return }
    if (-not $btnFilterToggle) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketFilter") | Out-Null; return }
    if (-not $filterPopup) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterPopup") | Out-Null; return }
    if (-not $filterPopupPanel) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterPopupPanel") | Out-Null; return }
    if (-not $filterActiveDot) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterActiveDot") | Out-Null; return }
    if (-not $btnToggleDetails) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnToggleTicketDetails") | Out-Null; return }
    if (-not $detailsPanel) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsPanel") | Out-Null; return }
    if (-not $detailsChevron) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsChevron") | Out-Null; return }
    if (-not $ticketBodyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketEmailBodyText") | Out-Null; return }
    if (-not $ticketReplyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplyText") | Out-Null; return }
    if (-not $btnSendReply) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnSendTicketReply") | Out-Null; return }
    if (-not $statusSelector) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketStatusSelector") | Out-Null; return }
    if (-not $btnSetStatus)   { [System.Windows.MessageBox]::Show("Missing XAML control: BtnSetTicketStatus") | Out-Null; return }
    if (-not $filterStatusNew) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterStatusNew") | Out-Null; return }
    if (-not $filterStatusInProgress) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterStatusInProgress") | Out-Null; return }
    if (-not $filterStatusWaitingOnUser) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterStatusWaitingOnUser") | Out-Null; return }
    if (-not $filterStatusNoLongerRequired) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterStatusNoLongerRequired") | Out-Null; return }
    if (-not $filterStatusCompleted) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterStatusCompleted") | Out-Null; return }
    if (-not $filterIncludeDeleted) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketFilterIncludeDeleted") | Out-Null; return }
    if (-not $btnFilterSelectAll) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketFilterSelectAllStatuses") | Out-Null; return }
    if (-not $btnFilterClearAll) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketFilterClearAllStatuses") | Out-Null; return }

    $script:TicketsGrid = $grid
    $script:TicketFilterActiveDot = $filterActiveDot
    $script:TicketFilterPopup = $filterPopup

    # Remove previous handlers safely
    try {
        if ($script:TicketsLoadedHandler) {
            $grid.RemoveHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)
        }
    } catch { }

    try {
        if ($script:TicketsRefreshHandler) {
            $btnRefresh.Remove_Click($script:TicketsRefreshHandler)
        }
    } catch { }

    try {
        if ($script:TicketsNewHandler) {
            $btnNew.Remove_Click($script:TicketsNewHandler)
        }
    } catch { }

    try {
        if ($script:TicketsDeleteHandler) {
            $btnDelete.Remove_Click($script:TicketsDeleteHandler)
        }
    } catch { }

    try {
        if ($script:TicketsRestoreHandler) {
            $btnRestore.Remove_Click($script:TicketsRestoreHandler)
        }
    } catch { }

    try {
        if ($script:TicketsStatusHandler) {
            $btnSetStatus.Remove_Click($script:TicketsStatusHandler)
        }
    } catch { }

    try {
        if ($script:TicketsFilterChangeHandler) {
            $filterStatusNew.Remove_Checked($script:TicketsFilterChangeHandler)
            $filterStatusNew.Remove_Unchecked($script:TicketsFilterChangeHandler)
            $filterStatusInProgress.Remove_Checked($script:TicketsFilterChangeHandler)
            $filterStatusInProgress.Remove_Unchecked($script:TicketsFilterChangeHandler)
            $filterStatusWaitingOnUser.Remove_Checked($script:TicketsFilterChangeHandler)
            $filterStatusWaitingOnUser.Remove_Unchecked($script:TicketsFilterChangeHandler)
            $filterStatusNoLongerRequired.Remove_Checked($script:TicketsFilterChangeHandler)
            $filterStatusNoLongerRequired.Remove_Unchecked($script:TicketsFilterChangeHandler)
            $filterStatusCompleted.Remove_Checked($script:TicketsFilterChangeHandler)
            $filterStatusCompleted.Remove_Unchecked($script:TicketsFilterChangeHandler)
            $filterIncludeDeleted.Remove_Checked($script:TicketsFilterChangeHandler)
            $filterIncludeDeleted.Remove_Unchecked($script:TicketsFilterChangeHandler)
            $filterStatusNew.Remove_Click($script:TicketsFilterChangeHandler)
            $filterStatusInProgress.Remove_Click($script:TicketsFilterChangeHandler)
            $filterStatusWaitingOnUser.Remove_Click($script:TicketsFilterChangeHandler)
            $filterStatusNoLongerRequired.Remove_Click($script:TicketsFilterChangeHandler)
            $filterStatusCompleted.Remove_Click($script:TicketsFilterChangeHandler)
            $filterIncludeDeleted.Remove_Click($script:TicketsFilterChangeHandler)
        }
    } catch { }

    try {
        if ($script:TicketsFilterSelectAllHandler) {
            $btnFilterSelectAll.Remove_Click($script:TicketsFilterSelectAllHandler)
        }
    } catch { }

    try {
        if ($script:TicketsFilterClearAllHandler) {
            $btnFilterClearAll.Remove_Click($script:TicketsFilterClearAllHandler)
        }
    } catch { }

    try {
        if ($script:TicketsFilterToggleHandler) {
            $btnFilterToggle.Remove_Click($script:TicketsFilterToggleHandler)
        }
    } catch { }

    try {
        if ($script:TicketsFilterPopupKeyHandler) {
            $filterPopupPanel.RemoveHandler([System.Windows.UIElement]::PreviewKeyDownEvent, $script:TicketsFilterPopupKeyHandler)
        }
    } catch { }

    try {
        if ($script:TicketsToggleDetailsHandler) {
            $btnToggleDetails.Remove_Click($script:TicketsToggleDetailsHandler)
        }
    } catch { }
    try {
        if ($script:TicketsSelectionChangedHandler) {
            $grid.RemoveHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:TicketsSelectionChangedHandler)
        }
    } catch { }

    try {
        if ($script:TicketsRowEditHandler) {
            $grid.remove_RowEditEnding($script:TicketsRowEditHandler)
        }
    } catch { }

    try {
        if ($script:TicketsSendReplyHandler) {
            $btnSendReply.Remove_Click($script:TicketsSendReplyHandler)
        }
    } catch { }
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


    $script:TicketFilterStatusBoxes = @{
        "New" = $filterStatusNew
        "In Progress" = $filterStatusInProgress
        "Waiting on User" = $filterStatusWaitingOnUser
        "No Longer Required" = $filterStatusNoLongerRequired
        "Completed" = $filterStatusCompleted
    }
    $script:TicketFilterIncludeDeleted = $filterIncludeDeleted

    Set-QOTicketFilterFromSettings -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $filterIncludeDeleted
    Update-QOTicketFilterIndicator -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted -Indicator $script:TicketFilterActiveDot
    Update-QOTicketDetailsView -Ticket $null -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron

    try {
        $statusList = & $getStatusesCmd
        if ($statusList) {
            $statusSelector.ItemsSource = @($statusList)
            if (-not $statusSelector.SelectedItem -and $statusSelector.Items.Count -gt 0) {
                $statusSelector.SelectedIndex = 0
            }
        }
    } catch { }

    $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Extended

    if ($grid.ContextMenu) {
        $grid.ContextMenu = $null
    }
    $script:TicketsStatusContextMenu = New-Object System.Windows.Controls.ContextMenu
    $statusMenuItems = @()
    if ($statusList) {
        $statusMenuItems = @($statusList)
    } else {
        $statusMenuItems = @("New", "In Progress", "Waiting on User", "No Longer Required", "Completed")
    }
    foreach ($status in $statusMenuItems) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = $status
        $menuItem.Tag = $status
        $script:TicketsStatusContextMenu.Items.Add($menuItem) | Out-Null
    }
    $grid.ContextMenu = $script:TicketsStatusContextMenu

    $script:TicketsStatusMenuItemHandler = {
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
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        } catch { }
    }.GetNewClosure()
    foreach ($menuItem in @($script:TicketsStatusContextMenu.Items)) {
        try { $menuItem.Add_Click($script:TicketsStatusMenuItemHandler) } catch { }
    }

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


    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        try {
            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            } else {
                Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
                Update-QOTicketFilterIndicator -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted -Indicator $script:TicketFilterActiveDot
            }
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)

    $script:TicketsRefreshHandler = {
        & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
    }.GetNewClosure()
    $btnRefresh.Add_Click($script:TicketsRefreshHandler)

    $script:TicketsToggleDetailsHandler = {
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

    $script:TicketsSelectionChangedHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        param($sender, $args)
        try {
            Update-QOTicketDetailsView -Ticket $grid.SelectedItem -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron
        } catch { }
    }.GetNewClosure()
    $grid.AddHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:TicketsSelectionChangedHandler)

    $script:TicketsRowEditHandler = {
        param($sender, $args)
        try {
            if ($args.EditAction -ne [System.Windows.Controls.DataGridEditAction]::Commit) { return }

            $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
            $ticket = $args.Row.Item
            if ($null -eq $ticket) { return }

            $null = & $updateTicketCmd -Ticket $ticket
        } catch { }
    }.GetNewClosure()
    $grid.add_RowEditEnding($script:TicketsRowEditHandler)

    $script:TicketsSendReplyHandler = {
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

    $script:TicketsNewHandler = {
        try {
            $ticket = & $newTicketCmd -Title "New ticket"
            $null   = & $addTicketCmd -Ticket $ticket

            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Update-QOTicketFilterIndicator -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted -Indicator $script:TicketFilterActiveDot

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

    $script:TicketsDeleteHandler = {
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
            $confirm = [System.Windows.MessageBox]::Show($confirmText,"Confirm","YesNo","Warning")
            if ($confirm -ne "Yes") { return }

            $null = & $removeCmd -Id $ids
            & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        }
        catch { }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)

    $script:TicketsRestoreHandler = {
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
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        }
        catch { }
    }.GetNewClosure()
    $btnRestore.Add_Click($script:TicketsRestoreHandler)

    $script:TicketsStatusHandler = {
        try {
            $selectedItems = @($grid.SelectedItems)
            if ($selectedItems.Count -eq 0) { return }

            $statusValue = [string]$statusSelector.SelectedItem
            if ([string]::IsNullOrWhiteSpace($statusValue)) { return }
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
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        }
        catch { }
    }.GetNewClosure()
    $btnSetStatus.Add_Click($script:TicketsStatusHandler)

    $script:TicketsFilterChangeHandler = {
        try {
            Save-QOTicketFilterSettings -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Update-QOTicketFilterIndicator -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted -Indicator $script:TicketFilterActiveDot
        } catch { }
    }.GetNewClosure()

    $filterStatusNew.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusNew.Add_Checked($script:TicketsFilterChangeHandler)
    $filterStatusNew.Add_Unchecked($script:TicketsFilterChangeHandler)
    $filterStatusInProgress.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusInProgress.Add_Checked($script:TicketsFilterChangeHandler)
    $filterStatusInProgress.Add_Unchecked($script:TicketsFilterChangeHandler)
    $filterStatusWaitingOnUser.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusWaitingOnUser.Add_Checked($script:TicketsFilterChangeHandler)
    $filterStatusWaitingOnUser.Add_Unchecked($script:TicketsFilterChangeHandler)
    $filterStatusNoLongerRequired.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusNoLongerRequired.Add_Checked($script:TicketsFilterChangeHandler)
    $filterStatusNoLongerRequired.Add_Unchecked($script:TicketsFilterChangeHandler)
    $filterStatusCompleted.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusCompleted.Add_Checked($script:TicketsFilterChangeHandler)
    $filterStatusCompleted.Add_Unchecked($script:TicketsFilterChangeHandler)
    $filterIncludeDeleted.Add_Click($script:TicketsFilterChangeHandler)
    $filterIncludeDeleted.Add_Checked($script:TicketsFilterChangeHandler)
    $filterIncludeDeleted.Add_Unchecked($script:TicketsFilterChangeHandler)

    $script:TicketsFilterSelectAllHandler = {
        try {
            foreach ($box in $script:TicketFilterStatusBoxes.Values) {
                $box.IsChecked = $true
            }
            Save-QOTicketFilterSettings -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Update-QOTicketFilterIndicator -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted -Indicator $script:TicketFilterActiveDot
        } catch { }
    }.GetNewClosure()
    $btnFilterSelectAll.Add_Click($script:TicketsFilterSelectAllHandler)

    $script:TicketsFilterClearAllHandler = {
        try {
            foreach ($box in $script:TicketFilterStatusBoxes.Values) {
                $box.IsChecked = $false
            }
            Save-QOTicketFilterSettings -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            Update-QOTicketFilterIndicator -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted -Indicator $script:TicketFilterActiveDot
        } catch { }
    }.GetNewClosure()
    $btnFilterClearAll.Add_Click($script:TicketsFilterClearAllHandler)

    $script:TicketsFilterToggleHandler = {
        try {
            $filterPopup.IsOpen = -not $filterPopup.IsOpen
            if ($filterPopup.IsOpen) {
                $filterPopupPanel.Focus() | Out-Null
            }
        } catch { }
    }.GetNewClosure()
    $btnFilterToggle.Add_Click($script:TicketsFilterToggleHandler)

    $script:TicketsFilterPopupKeyHandler = [System.Windows.Input.KeyEventHandler]{
        param($sender, $args)
        try {
            if ($args.Key -eq [System.Windows.Input.Key]::Escape) {
                $filterPopup.IsOpen = $false
                $args.Handled = $true
            }
        } catch { }
    }.GetNewClosure()
    $filterPopupPanel.AddHandler([System.Windows.UIElement]::PreviewKeyDownEvent, $script:TicketsFilterPopupKeyHandler)

    if ($syncCmd) {
        $script:TicketsAutoRefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:TicketsAutoRefreshTimer.Interval = [TimeSpan]::FromSeconds(60)
        $script:TicketsAutoRefreshTimer.Add_Tick({
            if ($script:TicketsAutoRefreshInProgress) { return }
            $script:TicketsAutoRefreshInProgress = $true
            try {
                if (-not $grid.IsLoaded) { return }
                & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            } catch { }
            finally {
                $script:TicketsAutoRefreshInProgress = $false
            }
        }.GetNewClosure())
        $script:TicketsAutoRefreshTimer.Start()
    }

    Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
