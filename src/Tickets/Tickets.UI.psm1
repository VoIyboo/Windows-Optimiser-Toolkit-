# Tickets.UI.psm1
# WPF UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1" -Force

# Script-level references
$script:TicketsGrid        = $null
$script:TicketsCollection  = $null
$script:BtnNewTicket       = $null
$script:BtnRefreshTickets  = $null

function Get-QOTicketsCollection {
    if (-not $script:TicketsCollection) {
        $script:TicketsCollection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    }
    return $script:TicketsCollection
}

function Refresh-QOTicketsGrid {
    if (-not $script:TicketsGrid) {
        return
    }

    $db = Get-QOTickets
    $tickets = @()
    if ($db.Tickets) {
        $tickets = @($db.Tickets)
    }

    $collection = Get-QOTicketsCollection
    $collection.Clear()

    foreach ($t in $tickets) {
        $collection.Add($t)
    }

    $script:TicketsGrid.ItemsSource = $collection
}

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory = $true)]
        $TicketsGrid,

        [Parameter(Mandatory = $true)]
        $BtnNewTicket,

        [Parameter(Mandatory = $true)]
        $BtnRefreshTickets
    )

    $script:TicketsGrid       = $TicketsGrid
    $script:BtnNewTicket      = $BtnNewTicket
    $script:BtnRefreshTickets = $BtnRefreshTickets

    # First load
    Refresh-QOTicketsGrid

    # Wire buttons
    if ($script:BtnRefreshTickets) {
        $script:BtnRefreshTickets.Add_Click({
            Refresh-QOTicketsGrid
        })
    }

    if ($script:BtnNewTicket) {
        $script:BtnNewTicket.Add_Click({
            try {
                $title = "Test ticket " + (Get-Date -Format 'HH:mm:ss')
                $desc  = "Created from Quinn Tickets tab preview."

                $ticket = New-QOTicket -Title $title -Description $desc -Category 'Testing' -Priority 'Low'
                Add-QOTicket -Ticket $ticket | Out-Null

                $collection = Get-QOTicketsCollection
                $collection.Add($ticket)
            }
            catch {
                # In a future version we can surface this nicely in the UI
                Write-Host "Error creating test ticket: $_"
            }
        })
    }
}

Export-ModuleMember -Function `
    Get-QOTicketsCollection, `
    Refresh-QOTicketsGrid, `
    Initialize-QOTicketsUI
