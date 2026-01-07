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

$script:TicketFilterStatusBoxes = $null
$script:TicketFilterIncludeDeleted = $null

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
        $items = & $GetTicketsCmd -Status $Statuses -IncludeDeleted:$IncludeDeleted
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
        [Parameter(Mandatory)][hashtable]$StatusBoxes,
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $statuses = @(
        $StatusBoxes.GetEnumerator() |
            Where-Object { $_.Value -and $_.Value.IsChecked } |
            ForEach-Object { $_.Key }
    )

    $includeDeleted = $false
    try { $includeDeleted = ($IncludeDeletedBox.IsChecked -eq $true) } catch { }

    return [pscustomobject]@{
        Statuses = $statuses
        IncludeDeleted = $includeDeleted
    }
}

function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [hashtable]$StatusBoxes,
        [System.Windows.Controls.CheckBox]$IncludeDeletedBox
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
        [Parameter(Mandatory)][hashtable]$StatusBoxes,
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$IncludeDeletedBox
    )

    $filterState = Get-QOTicketFilterState -StatusBoxes $StatusBoxes -IncludeDeletedBox $IncludeDeletedBox
    Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd -Statuses $filterState.Statuses -IncludeDeleted:$filterState.IncludeDeleted
}

function Initialize-QOTicketsUI {
    param([Parameter(Mandatory)]$Window)

    Add-Type -AssemblyName PresentationFramework | Out-Null

    # Capture core commands now
    $getTicketsCmd = Get-Command Get-QOTicketsFiltered -ErrorAction Stop
    $newTicketCmd  = Get-Command New-QOTicket  -ErrorAction Stop
    $addTicketCmd  = Get-Command Add-QOTicket  -ErrorAction Stop
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
    $btnRestore = $Window.FindName("BtnRestoreTicket")
    $statusSelector = $Window.FindName("TicketStatusSelector")
    $btnSetStatus = $Window.FindName("BtnSetTicketStatus")
    $filterStatusNew = $Window.FindName("FilterStatusNew")
    $filterStatusInProgress = $Window.FindName("FilterStatusInProgress")
    $filterStatusWaitingOnUser = $Window.FindName("FilterStatusWaitingOnUser")
    $filterStatusNoLongerRequired = $Window.FindName("FilterStatusNoLongerRequired")
    $filterStatusCompleted = $Window.FindName("FilterStatusCompleted")
    $filterIncludeDeleted = $Window.FindName("FilterIncludeDeleted")
    $btnFilterSelectAll = $Window.FindName("BtnFilterSelectAllStatuses")
    $btnFilterClearAll = $Window.FindName("BtnFilterClearAllStatuses")

    if (-not $grid)       { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }
    if (-not $btnRestore) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRestoreTicket") | Out-Null; return }
    if (-not $statusSelector) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketStatusSelector") | Out-Null; return }
    if (-not $btnSetStatus)   { [System.Windows.MessageBox]::Show("Missing XAML control: BtnSetTicketStatus") | Out-Null; return }
    if (-not $filterStatusNew) { [System.Windows.MessageBox]::Show("Missing XAML control: FilterStatusNew") | Out-Null; return }
    if (-not $filterStatusInProgress) { [System.Windows.MessageBox]::Show("Missing XAML control: FilterStatusInProgress") | Out-Null; return }
    if (-not $filterStatusWaitingOnUser) { [System.Windows.MessageBox]::Show("Missing XAML control: FilterStatusWaitingOnUser") | Out-Null; return }
    if (-not $filterStatusNoLongerRequired) { [System.Windows.MessageBox]::Show("Missing XAML control: FilterStatusNoLongerRequired") | Out-Null; return }
    if (-not $filterStatusCompleted) { [System.Windows.MessageBox]::Show("Missing XAML control: FilterStatusCompleted") | Out-Null; return }
    if (-not $filterIncludeDeleted) { [System.Windows.MessageBox]::Show("Missing XAML control: FilterIncludeDeleted") | Out-Null; return }
    if (-not $btnFilterSelectAll) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnFilterSelectAllStatuses") | Out-Null; return }
    if (-not $btnFilterClearAll) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnFilterClearAllStatuses") | Out-Null; return }

    $script:TicketsGrid = $grid

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

    $script:TicketFilterStatusBoxes = @{
        "New" = $filterStatusNew
        "In Progress" = $filterStatusInProgress
        "Waiting on User" = $filterStatusWaitingOnUser
        "No Longer Required" = $filterStatusNoLongerRequired
        "Completed" = $filterStatusCompleted
    }
    $script:TicketFilterIncludeDeleted = $filterIncludeDeleted

    foreach ($box in $script:TicketFilterStatusBoxes.Values) {
        $box.IsChecked = $true
    }
    $filterIncludeDeleted.IsChecked = $false

    try {
        $statusList = & $getStatusesCmd
        if ($statusList) {
            $statusSelector.ItemsSource = @($statusList)
            if (-not $statusSelector.SelectedItem -and $statusSelector.Items.Count -gt 0) {
                $statusSelector.SelectedIndex = 0
            }
        }
    } catch { }

    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        try {
            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            } else {
                Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
            }
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)

    $script:TicketsRefreshHandler = {
        & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
    }.GetNewClosure()
    $btnRefresh.Add_Click($script:TicketsRefreshHandler)

    $script:TicketsNewHandler = {
        try {
            $ticket = & $newTicketCmd -Title "New ticket"
            $null   = & $addTicketCmd -Ticket $ticket

            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted

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
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
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
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        } catch { }
    }.GetNewClosure()

    $filterStatusNew.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusInProgress.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusWaitingOnUser.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusNoLongerRequired.Add_Click($script:TicketsFilterChangeHandler)
    $filterStatusCompleted.Add_Click($script:TicketsFilterChangeHandler)
    $filterIncludeDeleted.Add_Click($script:TicketsFilterChangeHandler)

    $script:TicketsFilterSelectAllHandler = {
        try {
            foreach ($box in $script:TicketFilterStatusBoxes.Values) {
                $box.IsChecked = $true
            }
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        } catch { }
    }.GetNewClosure()
    $btnFilterSelectAll.Add_Click($script:TicketsFilterSelectAllHandler)

    $script:TicketsFilterClearAllHandler = {
        try {
            foreach ($box in $script:TicketFilterStatusBoxes.Values) {
                $box.IsChecked = $false
            }
            Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
        } catch { }
    }.GetNewClosure()
    $btnFilterClearAll.Add_Click($script:TicketsFilterClearAllHandler)

    Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -StatusBoxes $script:TicketFilterStatusBoxes -IncludeDeletedBox $script:TicketFilterIncludeDeleted
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
