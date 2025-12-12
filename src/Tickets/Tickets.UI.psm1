# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"  -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction SilentlyContinue

# Guard so we do not re-save while we are applying the saved order
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

    # Allow inline editing (Title column is editable in XAML)
    $TicketsGrid.IsReadOnly = $false

    # Save column order when user drags headers left/right
    $TicketsGrid.Add_ColumnReordered({
        param($sender, $e)
        Save-QOTicketsColumnOrder -DataGrid $sender
    })

    # Save column widths when user resizes columns
    $TicketsGrid.Add_ColumnWidthChanged({
        param($sender, $e)
        Save-QOTicketsColumnWidths -DataGrid $sender
    })

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

    # Initial load
    Update-QOTicketsGrid

    # Apply saved layout (order + widths) after first load
    Apply-QOTicketsColumnLayout -DataGrid $TicketsGrid
}




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

    # Bind to the grid
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

        # Apply any previously saved column order
    Apply-QOTicketsColumnOrder -DataGrid $TicketsGrid

    # Save the column order when the user reorders columns
    $TicketsGrid.Add_ColumnReordered({
        param($sender, $eventArgs)

        # Prevent saving while we are *applying* a saved order
        if (-not $script:TicketsColumnOrderApplying) {
            Save-QOTicketsColumnOrder -DataGrid $sender
        }
    })


    # Allow inline editing (Title column is editable in XAML)
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

        # Do NOT call Update-QOTicketsGrid here,
        # it would fight with the active edit transaction.
    })

    # Initial load
    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid
