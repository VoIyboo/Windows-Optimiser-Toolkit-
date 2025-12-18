# src\Tickets\Tickets.UI.psm1
# UI wiring for the Tickets tab

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Force -ErrorAction Stop

$script:TicketsGrid = $null

function Initialize-QOTicketsUI {
    param([Parameter(Mandatory)] $Window)

    Add-Type -AssemblyName PresentationFramework | Out-Null
    Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

    $script:TicketsGrid = $Window.FindName("TicketsGrid")
    $btnRefresh = $Window.FindName("BtnTicketsRefresh")
    $btnAdd     = $Window.FindName("BtnTicketsAdd")
    $btnDelete  = $Window.FindName("BtnTicketsDelete")

    if (-not $script:TicketsGrid) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnRefresh) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketsRefresh") | Out-Null; return }
    if (-not $btnAdd)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketsAdd") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketsDelete") | Out-Null; return }

    $refresh = {
        try {
            $db = Get-QOTickets
            $script:TicketsGrid.ItemsSource = @($db.Tickets)
            $script:TicketsGrid.Items.Refresh()
        }
        catch {
            [System.Windows.MessageBox]::Show("Load tickets failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    }

    $btnRefresh.Add_Click($refresh)

    $btnAdd.Add_Click({
        try {
            $title = [Microsoft.VisualBasic.Interaction]::InputBox("Ticket title:", "New Ticket", "")
            if ([string]::IsNullOrWhiteSpace($title)) { return }

            $ticket = New-QOTicket -Title $title
            Add-QOTicket -Ticket $ticket | Out-Null

            & $refresh
        }
        catch {
            [System.Windows.MessageBox]::Show("Create ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    })

    $btnDelete.Add_Click({
        try {
            $selected = $script:TicketsGrid.SelectedItem
            if (-not $selected) {
                [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null
                return
            }

            $id = if ($selected.PSObject.Properties.Name -contains "Id") { [string]$selected.Id } else { "" }
            if ([string]::IsNullOrWhiteSpace($id)) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id, cannot delete.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show("Delete this ticket?", "Confirm", "YesNo", "Warning")
            if ($confirm -ne "Yes") { return }

            Remove-QOTicket -Id $id | Out-Null

            & $refresh
        }
        catch {
            [System.Windows.MessageBox]::Show("Delete ticket failed.`r`n$($_.Exception.Message)") | Out-Null
        }
    })

    & $refresh
}

Export-ModuleMember -Function Initialize-QOTicketsUI
