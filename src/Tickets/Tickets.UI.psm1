# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1" -Force -ErrorAction SilentlyContinue

function Update-QOTicketsGrid {
    try {
        # Get the full tickets DB
        $db = Get-QOTickets
        $tickets = @()
        if ($db.Tickets) {
            $tickets = @($db.Tickets)
        }
    }
    catch {
        Write-Warning "Tickets UI: failed to load tickets. $_"
        $tickets = @()
    }

    $view = foreach ($t in $tickets) {

        # Normalise/format Created time, drop seconds and use local PC time
        $created = $null
        $raw = $null

        if ($t.PSObject.Properties.Name -contains 'CreatedAt') {
            $raw = $t.CreatedAt
        }

        if ($raw -is [datetime]) {
            $created = $raw
        }
        elseif ($raw) {
            [datetime]::TryParse($raw, [ref]$created) | Out-Null
        }

        if ($created) {
            # Example: 12/11/2025 11:09 PM (no seconds)
            $createdString = $created.ToString('dd/MM/yyyy h:mm tt')
        }
        else {
            $createdString = $raw
        }

        [PSCustomObject]@{
            Id        = $t.Id
            CreatedAt = $createdString
            Status    = $t.Status
            Priority  = $t.Priority
            Title     = $t.Title
            Category  = $t.Category
        }
    }

    # Just set ItemsSource once with the view list
    $script:TicketsGrid.ItemsSource = $view
}

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid,

        [Parameter(Mandatory)]
        $BtnRefreshTickets,

        [Parameter(Mandatory)]
        $BtnNewTicket
    )

    # Keep references for later
    $script:TicketsGrid = $TicketsGrid

    # Allow editing in the grid (Title column is editable in XAML)
    $TicketsGrid.IsReadOnly = $false

    # Refresh button
    $BtnRefreshTickets.Add_Click({
        Update-QOTicketsGrid
    })

    # New test ticket button
    $BtnNewTicket.Add_Click({
        try {
            $now = Get-Date

            # New-QOTicket creates the in-memory ticket
            $ticket = New-QOTicket `
                -Title ("Test ticket {0}" -f $now.ToString("HH:mm")) `
                -Description "Test ticket created from the UI." `
                -Category "Testing" `
                -Priority "Low"

            # Add-QOTicket saves it into Tickets.json
            Add-QOTicket -Ticket $ticket | Out-Null
        }
        catch {
            Write-Warning "Tickets UI: failed to create test ticket. $_"
        }

        Update-QOTicketsGrid
    })

    # When a cell finishes editing, persist Title changes
    $TicketsGrid.Add_CellEditEnding({
        param($sender, $e)

        # We only care about the Title column
        if ($e.Column.Header -ne 'Title') { return }

        $row = $e.Row.Item
        if (-not $row) { return }

        $ticketId = $row.Id
        if ([string]::IsNullOrWhiteSpace($ticketId)) { return }

        # For DataGridTextColumn this is a TextBox
        $newTitle = $e.EditingElement.Text

        try {
            Set-QOTicketTitle -Id $ticketId -Title $newTitle | Out-Null
        }
        catch {
            Write-Warning "Tickets UI: failed to save edited title. $_"
        }

        # Important: do NOT call Update-QOTicketsGrid here,
        # it would fight with the edit transaction and cause errors.
    })

    # Initial load
    Update-QOTicketsGrid
}


    # NOTE:
    # For now we let WPF handle inline Title editing in-memory only.
    # No popups, no extra windows, no ItemsSource reset during edit.
    # Later we can add a "Save changes" button that walks the grid
    # and syncs titles back into the JSON file.

    # Initial load
    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid
