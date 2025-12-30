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

    # Capture core commands now
    $getTicketsCmd = Get-Command Get-QOTickets -ErrorAction Stop
    $newTicketCmd  = Get-Command New-QOTicket  -ErrorAction Stop
    $addTicketCmd  = Get-Command Add-QOTicket  -ErrorAction Stop
    $removeCmd     = Get-Command Remove-QOTicket -ErrorAction Stop

    $syncCmd = $null
    try { $syncCmd = Get-Command Sync-QOTicketsFromEmail -ErrorAction Stop } catch { $syncCmd = $null }

    # Capture UI local function commands (IMPORTANT: event handlers may not resolve them by name)
    $refreshGridCmd = Get-Command Refresh-QOTicketsGrid -ErrorAction Stop
    $emailSyncAndRefreshCmd = Get-Command Invoke-QOTicketsEmailSyncAndRefresh -ErrorAction Stop

    Write-QOTicketsUILog ("Captured Get-QOTickets from: " + $getTicketsCmd.Source)
    Write-QOTicketsUILog ("Captured New-QOTicket from: " + $newTicketCmd.Source)
    Write-QOTicketsUILog ("Captured Add-QOTicket from: " + $addTicketCmd.Source)
    Write-QOTicketsUILog ("Captured Remove-QOTicket from: " + $removeCmd.Source)
    Write-QOTicketsUILog ("Captured Sync-QOTicketsFromEmail from: " + (($syncCmd.Source) + ""))
    Write-QOTicketsUILog ("Captured Refresh-QOTicketsGrid from: " + $refreshGridCmd.Source)
    Write-QOTicketsUILog ("Captured Invoke-QOTicketsEmailSyncAndRefresh from: " + $emailSyncAndRefreshCmd.Source)

    # Capture stable local references for closures
    $grid       = $Window.FindName("TicketsGrid")
    $btnRefresh = $Window.FindName("BtnRefreshTickets")
    $btnNew     = $Window.FindName("BtnNewTicket")
    $btnDelete  = $Window.FindName("BtnDeleteTicket")

    if (-not $grid)       { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }

    # Keep script state too (for anything else that references it)
    $script:TicketsGrid = $grid

    # Remove previous handlers
    try {
        if ($script:TicketsLoadedHandler) {
            $grid.RemoveHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)
        }
    } catch { }

    try { if ($script:TicketsRefreshHandler) { $btnRefresh.Remove_Click($script:TicketsRefreshHandler) } } catch { }
    try { if ($script:TicketsNewHandler)     { $btnNew.Remove_Click($script:TicketsNewHandler) } } catch { }
    try { if ($script:TicketsDeleteHandler)  { $btnDelete.Remove_Click($script:TicketsDeleteHandler) } } catch { }

    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        try {
            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd
            } else {
                & $refreshGridCmd -Grid $grid -GetTicketsCmd $getTicketsCmd
            }
        } catch { }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)

    $script:TicketsRefreshHandler = {
        & $emailSyncAndRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd
    }.GetNewClosure()
    $btnRefresh.Add_Click($script:TicketsRefreshHandler)

    $script:TicketsNewHandler = {
        try {
            $ticket = & $newTicketCmd -Title "New ticket"
            $null   = & $addTicketCmd -Ticket $ticket

            & $refreshGridCmd -Grid $grid -GetTicketsCmd $getTicketsCmd

            $grid.SelectedItem = $ticket
            $grid.ScrollIntoView($ticket)

            if ($grid.Columns.Count -gt 0) {
                $grid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo($ticket, $grid.Columns[0])
                $grid.BeginEdit()
            }
        }
        catch {
            try { Write-QOTicketsUILog ("Create ticket failed: " + $_.Exception.ToString()) "ERROR" } catch { }
            [System.Windows.MessageBox]::Show("Create ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnNew.Add_Click($script:TicketsNewHandler)

    $script:TicketsDeleteHandler = {
        try {
            $selected = $grid.SelectedItem
            if (-not $selected) { [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null; return }

            if (-not ($selected.PSObject.Properties.Name -contains "Id")) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show("Delete this ticket?","Confirm","YesNo","Warning")
            if ($confirm -ne "Yes") { return }

            $null = & $removeCmd -Id $selected.Id
            & $refreshGridCmd -Grid $grid -GetTicketsCmd $getTicketsCmd
        }
        catch {
            [System.Windows.MessageBox]::Show("Delete ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)

    & $refreshGridCmd -Grid $grid -GetTicketsCmd $getTicketsCmd
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
