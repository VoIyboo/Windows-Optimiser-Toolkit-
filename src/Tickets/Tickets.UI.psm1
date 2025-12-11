# Tickets.UI.psm1
# WPF UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1" -Force

# Script-level references
$script:TicketsGrid       = $null
$script:BtnNewTicket      = $null
$script:BtnRefreshTickets = $null

function Refresh-QOTicketsGrid {
    <#
        Reloads tickets from the JSON database and binds them to the grid.
    #>

    if (-not $script:TicketsGrid) {
        return
    }

    $db = Get-QOTickets

    $tickets = @()
    if ($db.Tickets) {
        $tickets = @($db.Tickets)
    }

    # Bind simple array to the DataGrid
    $script:TicketsGrid.ItemsSource = $tickets
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

    # Cache controls
    $script:TicketsGrid       = $TicketsGrid
    $script:BtnNewTicket      = $BtnNewTicket
    $script:BtnRefreshTickets = $BtnRefreshTickets

    # First load
    Refresh-QOTicketsGrid

    # Wire Refresh button
    if ($script:BtnRefreshTickets) {
        $script:BtnRefreshTickets.Add_Click({
            Refresh-QOTicketsGrid
        })
    }

    # Wire "New test ticket" button
    if ($script:BtnNewTicket) {
        $script:BtnNewTicket.Add_Click({
            try {
                $title = "Test ticket " + (Get-Date -Format 'HH:mm:ss')
                $desc  = "Created from Quinn Tickets tab preview."

                $ticket = New-QOTicket -Title $title `
                                       -Description $desc `
                                       -Category 'Testing' `
                                       -Priority 'Low'
