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

# -------------------------
# Logging helper
# -------------------------
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

# -------------------------
# Data helpers
# -------------------------
function Get-QOTicketsForGrid {
    try {
        if (-not (Get-Command Get-QOTickets -ErrorAction SilentlyContinue)) {
            return @()
        }

        $db = Get-QOTickets
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
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try {
        $items = @(Get-QOTicketsForGrid)
        $Grid.ItemsSource = $items
        $Grid.Items.Refresh()
    }
    catch {
        [System.Windows.MessageBox]::Show("Load tickets failed.`r`n$($_.Exception.Message)") | Out-Null
    }
}

# -------------------------
# Email sync + refresh
# -------------------------
function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    Write-QOTicketsUILog "Tickets: Email sync started"

    try {
        if (Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue) {
            Sync-QOTicketsFromEmail | Out-Null
            Write-QOTicketsUILog "Tickets: Email sync finished"
        } else {
            Write-QOTicketsUILog "Tickets: Sync-QOTicketsFromEmail not found (skipping)" "WARN"
        }
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Email sync failed: " + $_.Exception.Message) "ERROR"
    }

    Refresh-QOTicketsGrid -Grid $Grid
}

# -------------------------
# Main wiring
# -------------------------
function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework | Out-Null

    $script:TicketsGrid = $Window.FindName("TicketsGrid")
    $btnRefresh         = $Window.FindName("BtnRefreshTickets")
    $btnNew             = $Window.FindName("BtnNewTicket")
    $btnDelete          = $Window.FindName("BtnDeleteTicket")

    if (-not $script:TicketsGrid) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh)         { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null; return }
    if (-not $btnNew)             { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)          { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }

    # ----------------------------------------
    # Remove previous handlers (prevents lag)
    # ----------------------------------------
    try {
        if ($script:TicketsLoadedHandler) {
            $script:TicketsGrid.RemoveHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)
        }
    } catch { }

    try { if ($script:TicketsRefreshHandler) { $btnRefresh.Remove_Click($script:TicketsRefreshHandler) } } catch { }
    try { if ($script:TicketsNewHandler)     { $btnNew.Remove_Click($script:TicketsNewHandler) } } catch { }
    try { if ($script:TicketsDeleteHandler)  { $btnDelete.Remove_Click($script:TicketsDeleteHandler) } } catch { }

    # ----------------------------------------
    # One time sync when the grid first loads
    # ----------------------------------------
    $script:TicketsLoadedHandler = [System.Windows.RoutedEventHandler]{
        try {
            if (-not $script:TicketsEmailSyncRan) {
                $script:TicketsEmailSyncRan = $true
                Invoke-QOTicketsEmailSyncAndRefresh -Grid $script:TicketsGrid
            } else {
                Refresh-QOTicketsGrid -Grid $script:TicketsGrid
            }
        } catch { }
    }.GetNewClosure()

    $script:TicketsGrid.AddHandler([System.Windows.FrameworkElement]::LoadedEvent, $script:TicketsLoadedHandler)

    # ----------------------------------------
    # Refresh button runs sync
    # ----------------------------------------
    $script:TicketsRefreshHandler = {
        Invoke-QOTicketsEmailSyncAndRefresh -Grid $script:TicketsGrid
    }.GetNewClosure()
    $btnRefresh.Add_Click($script:TicketsRefreshHandler)

    # ----------------------------------------
    # New ticket (inline edit)
    # ----------------------------------------
    $script:TicketsNewHandler = {
        try {
            if (-not (Get-Command New-QOTicket -ErrorAction SilentlyContinue)) { throw "New-QOTicket not found" }
            if (-not (Get-Command Add-QOTicket -ErrorAction SilentlyContinue)) { throw "Add-QOTicket not found" }

            $ticket = New-QOTicket -Title "New ticket"
            Add-QOTicket -Ticket $ticket | Out-Null

            Refresh-QOTicketsGrid -Grid $script:TicketsGrid

            $script:TicketsGrid.SelectedItem = $ticket
            $script:TicketsGrid.ScrollIntoView($ticket)

            if ($script:TicketsGrid.Columns.Count -gt 0) {
                $script:TicketsGrid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo(
                    $ticket,
                    $script:TicketsGrid.Columns[0]
                )
                $script:TicketsGrid.BeginEdit()
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Create ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnNew.Add_Click($script:TicketsNewHandler)

    # ----------------------------------------
    # Delete ticket
    # ----------------------------------------
    $script:TicketsDeleteHandler = {
        try {
            if (-not (Get-Command Remove-QOTicket -ErrorAction SilentlyContinue)) { throw "Remove-QOTicket not found" }

            $selected = $script:TicketsGrid.SelectedItem
            if (-not $selected) { [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null; return }

            if (-not ($selected.PSObject.Properties.Name -contains "Id")) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show("Delete this ticket?", "Confirm", "YesNo", "Warning")
            if ($confirm -ne "Yes") { return }

            Remove-QOTicket -Id $selected.Id | Out-Null
            Refresh-QOTicketsGrid -Grid $script:TicketsGrid
        }
        catch {
            [System.Windows.MessageBox]::Show("Delete ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)

    # ----------------------------------------
    # Initial load (fast)
    # ----------------------------------------
    Refresh-QOTicketsGrid -Grid $script:TicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Invoke-QOTicketsEmailSyncAndRefresh
