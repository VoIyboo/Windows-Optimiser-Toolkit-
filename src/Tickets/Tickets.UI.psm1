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
    param([Parameter(Mandatory)]$GetTicketsCmd)

    try {
        $db = & $GetTicketsCmd
        if ($null -eq $db) { return @() }

        if ($db.PSObject.Properties.Name -contains "Tickets") {
            return @($db.Tickets)
        }

        if ($db -is [System.Collections.IEnumerable]) {
            return @($db)
        }

        return @()
    }
    catch {
        return @()
    }
}

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd
    )

    try {
        $items = @(Get-QOTicketsForGrid -GetTicketsCmd $GetTicketsCmd)
        $Grid.ItemsSource = $items
        $Grid.Items.Refresh()
    }
    catch {
        [System.Windows.MessageBox]::Show("Load tickets failed.`r`n$($_.Exception.Message)") | Out-Null
    }
}

function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd
    )

    Write-QOTicketsUILog "Tickets: Email sync started"

    try {
        if ($SyncCmd) {
            & $SyncCmd | Out-Null
            Write-QOTicketsUILog "Tickets: Email sync finished"
        } else {
            Write-QOTicketsUILog "Tickets: Sync command not available (skipping)" "WARN"
        }
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Email sync failed: " + $_.Exception.Message) "ERROR"
    }

    Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd
}

function Initialize-QOTicketsUI {
    param([Parameter(Mandatory)]$Window)

    Add-Type -AssemblyName PresentationFramework | Out-Null

    # Capture commands now (core + local module helpers)
    $getTicketsCmd = Get-Command Get-QOTickets -ErrorAction Stop
    $newTicketCmd  = Get-Command New-QOTicket  -ErrorAction Stop
    $addTicketCmd  = Get-Command Add-QOTicket  -ErrorAction Stop
    $removeCmd     = Get-Command Remove-QOTicket -ErrorAction Stop

    $refreshCmd    = Get-Command Refresh-QOTicketsGrid -ErrorAction Stop
    $emailSyncCmd  = Get-Command Invoke-QOTicketsEmailSyncAndRefresh -ErrorAction Stop

    $syncCmd = $null
    try { $syncCmd = Get-Command Sync-QOTicketsFromEmail -ErrorAction Stop } catch { $syncCmd = $null }

    Write-QOTicketsUILog ("Captured Get-QOTickets from: " + $getTicketsCmd.Source)
    Write-QOTicketsUILog ("Captured New-QOTicket from: " + $newTicketCmd.Source)
    Write-QOTicketsUILog ("Captured Add-QOTicket from: " + $addTicketCmd.Source)
    Write-QOTicketsUILog ("Captured Remove-QOTicket from: " + $removeCmd.Source)
    Write-QOTicketsUILog ("Captured Refresh-QOTicketsGrid from: " + $refreshCmd.Source)
    Write-QOTicketsUILog ("Captured Invoke-QOTicketsEmailSyncAndRefresh from: " + $emailSyncCmd.Source)
    Write-QOTicketsUILog ("Captured Sync-QOTicketsFromEmail from: " + (($syncCmd.Source) + ""))

    # Locate controls
    $script:TicketsGrid = $Window.FindName("TicketsGrid")
    $btnRefresh         = $Window.FindName("BtnRefreshTickets")
    $btnNew             = $Window.FindName("BtnNewTicket")
    $btnDelete          = $Window.FindName("BtnDeleteTicket")

    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }

    if (-not $script:TicketsGrid) {
        Write-QOTicketsUILog "TicketsGrid not found at init, will re-resolve on demand" "WARN"
    }

    # Helper: ensure grid exists (tabs/templates can delay element creation)
    $ensureGrid = {
        if (-not $script:TicketsGrid) {
            $script:TicketsGrid = $Window.FindName("TicketsGrid")
        }

        if (-not $script:TicketsGrid) {
            [System.Windows.MessageBox]::Show(
                "TicketsGrid is missing. Check MainWindow.xaml: DataGrid Name/x:Name must be exactly 'TicketsGrid'.",
                "Quinn Optimiser Toolkit"
            ) | Out-Null
            return $false
        }

        return $true
    }.GetNewClosure()

    # Remove previous handlers
    try {
        if ($script:TicketsLoadedHandler -and $script:TicketsGrid) {
            $script:TicketsGrid.RemoveHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)
        }
    } catch { }

    try { if ($script:TicketsRefreshHandler) { $btnRefresh.Remove_Click($script:TicketsRefreshHandler) } } catch { }
    try { if ($script:TicketsNewHandler)     { $btnNew.Remove_Click($script:TicketsNewHandler) } } catch { }
    try { if ($script:TicketsDeleteHandler)  { $btnDelete.Remove_Click($script:TicketsDeleteHandler) } } catch { }

    # Loaded event (runs when grid actually exists)
    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        try {
            if (-not (& $ensureGrid)) { return }

            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                & $emailSyncCmd -Grid $script:TicketsGrid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd
            } else {
                & $refreshCmd -Grid $script:TicketsGrid -GetTicketsCmd $getTicketsCmd
            }
        } catch { }
    }.GetNewClosure()

    # Only attach Loaded handler if grid exists now, otherwise it will attach once grid is found
    if ($script:TicketsGrid) {
        $script:TicketsGrid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)
    }

    # Refresh click
    $script:TicketsRefreshHandler = {
        try {
            if (-not (& $ensureGrid)) { return }
            & $emailSyncCmd -Grid $script:TicketsGrid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd
        } catch {
            [System.Windows.MessageBox]::Show("Refresh failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnRefresh.Add_Click($script:TicketsRefreshHandler)

    # New ticket click
    $script:TicketsNewHandler = {
        try {
            if (-not (& $ensureGrid)) { return }

            $ticket = & $newTicketCmd -Title "New ticket"
            $null   = & $addTicketCmd -Ticket $ticket

            & $refreshCmd -Grid $script:TicketsGrid -GetTicketsCmd $getTicketsCmd

            $script:TicketsGrid.SelectedItem = $ticket
            $script:TicketsGrid.ScrollIntoView($ticket)

            if ($script:TicketsGrid.Columns.Count -gt 0) {
                $script:TicketsGrid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo($ticket, $script:TicketsGrid.Columns[0])
                $script:TicketsGrid.BeginEdit()
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Create ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnNew.Add_Click($script:TicketsNewHandler)

    # Delete ticket click
    $script:TicketsDeleteHandler = {
        try {
            if (-not (& $ensureGrid)) { return }

            $selected = $script:TicketsGrid.SelectedItem
            if (-not $selected) { [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null; return }

            if (-not ($selected.PSObject.Properties.Name -contains "Id")) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show("Delete this ticket?","Confirm","YesNo","Warning")
            if ($confirm -ne "Yes") { return }

            $null = & $removeCmd -Id $selected.Id
            & $refreshCmd -Grid $script:TicketsGrid -GetTicketsCmd $getTicketsCmd
        }
        catch {
            [System.Windows.MessageBox]::Show("Delete ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)

    # Initial refresh (only if grid exists now)
    try {
        if ($script:TicketsGrid) {
            & $refreshCmd -Grid $script:TicketsGrid -GetTicketsCmd $getTicketsCmd
        }
    } catch { }
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
