# src\Tickets\Tickets.UI.psm1
# UI wiring for the Tickets tab (NO storage logic here)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1")   -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\Core\Settings.psm1") -Force -ErrorAction Stop

$script:TicketsGrid = $null

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    if (-not $Window) { throw "Initialize-QOTicketsUI: Window is null." }

    $script:TicketsGrid = $Window.FindName("TicketsGrid")
    $btnRefresh         = $Window.FindName("BtnTicketsRefresh")
    $btnAdd             = $Window.FindName("BtnTicketsAdd")
    $btnDelete          = $Window.FindName("BtnTicketsDelete")

    if (-not $script:TicketsGrid) { [System.Windows.MessageBox]::Show("TicketsGrid not found. Check XAML Name=""TicketsGrid""") | Out-Null; return }
    if (-not $btnRefresh)         { [System.Windows.MessageBox]::Show("BtnTicketsRefresh not found. Check XAML Name=""BtnTicketsRefresh""") | Out-Null; return }
    if (-not $btnAdd)             { [System.Windows.MessageBox]::Show("BtnTicketsAdd not found. Check XAML Name=""BtnTicketsAdd""") | Out-Null; return }
    if (-not $btnDelete)          { [System.Windows.MessageBox]::Show("BtnTicketsDelete not found. Check XAML Name=""BtnTicketsDelete""") | Out-Null; return }

    $refresh = {
        try {
            $db = Get-QOTickets
            $script:TicketsGrid.ItemsSource = @($db.Tickets)
            $script:TicketsGrid.Items.Refresh()
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to load tickets.`r`n$($_.Exception.Message)") | Out-Null
        }
    }

    $btnRefresh.Add_Click($refresh)

    $btnAdd.Add_Click({
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null
            $title = [Microsoft.VisualBasic.Interaction]::InputBox("Ticket title:", "New Ticket", "")
            if ([string]::IsNullOrWhiteSpace($title)) { return }

            $t = New-QOTicket -Title $title
            Add-QOTicket -Ticket $t

            & $refresh
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to create ticket.`r`n$($_.Exception.Message)") | Out-Null
        }
    })

    $btnDelete.Add_Click({
        try {
            $selected = $script:TicketsGrid.SelectedItem
            if (-not $selected) {
                [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null
                return
            }

            $id = $null
            if ($selected.PSObject.Properties.Name -contains "Id") { $id = [string]$selected.Id }
            if ([string]::IsNullOrWhiteSpace($id)) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id. Cannot delete.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show(
                "Delete this ticket?", "Confirm delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )

            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

            Remove-QOTicket -Id $id

            & $refresh
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to delete ticket.`r`n$($_.Exception.Message)") | Out-Null
        }
    })

    & $refresh
}

Export-ModuleMember -Function Initialize-QOTicketsUI
