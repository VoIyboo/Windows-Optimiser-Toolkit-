# src\Tickets\Tickets.UI.psm1
# UI wiring for Tickets tab

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Force -ErrorAction Stop

$script:TicketsGrid = $null

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

    if (-not $script:TicketsGrid) {
        [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null
        return
    }
    if (-not $btnRefresh) {
        [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null
        return
    }
    if (-not $btnNew) {
        [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null
        return
    }
    if (-not $btnDelete) {
        [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null
        return
    }

    # ------------------------------------------------------------
    # Refresh helper (safe, no call operator)
    # ------------------------------------------------------------
    $refresh = {
        try {
            $db = Get-QOTickets
            $script:TicketsGrid.ItemsSource = @($db.Tickets)
            $script:TicketsGrid.Items.Refresh()
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Load tickets failed.`r`n$($_.Exception.Message)"
            ) | Out-Null
        }
    }

    $btnRefresh.Add_Click({
        & $refresh
    })

    # ------------------------------------------------------------
    # New ticket (NO POPUPS, inline edit)
    # ------------------------------------------------------------
    $btnNew.Add_Click({
        try {
            # Create ticket with placeholder title
            $ticket = New-QOTicket -Title "New ticket"
            Add-QOTicket -Ticket $ticket | Out-Null

            # Reload grid
            $db = Get-QOTickets
            $script:TicketsGrid.ItemsSource = @($db.Tickets)
            $script:TicketsGrid.Items.Refresh()

            # Select + focus new row
            $script:TicketsGrid.SelectedItem = $ticket
            $script:TicketsGrid.ScrollIntoView($ticket)

            # Begin editing Title cell (first column)
            $script:TicketsGrid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo(
                $ticket,
                $script:TicketsGrid.Columns[0]
            )

            $script:TicketsGrid.BeginEdit()
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Create ticket failed.`r`n$($_.Exception.Message)"
            ) | Out-Null
        }
    })

    # ------------------------------------------------------------
    # Delete ticket
    # ------------------------------------------------------------
    $btnDelete.Add_Click({
        try {
            $selected = $script:TicketsGrid.SelectedItem
            if (-not $selected) {
                [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null
                return
            }

            if (-not ($selected.PSObject.Properties.Name -contains "Id")) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show(
                "Delete this ticket?",
                "Confirm",
                "YesNo",
                "Warning"
            )

            if ($confirm -ne "Yes") { return }

            Remove-QOTicket -Id $selected.Id | Out-Null
            & $refresh
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Delete ticket failed.`r`n$($_.Exception.Message)"
            ) | Out-Null
        }
    })

    # Initial load
    & $refresh
}

Export-ModuleMember -Function Initialize-QOTicketsUI
