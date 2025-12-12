# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

function Update-QOTicketsGrid {
    try {
        $tickets = Get-QOTickets
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
            # Example: 12/11/2025 11:09 PM  (no seconds)
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

    # Refresh button
    $BtnRefreshTickets.Add_Click({
        Update-QOTicketsGrid
    })

    # New test ticket button
    $BtnNewTicket.Add_Click({
        try {
            $now = Get-Date
            New-QOTTicket `
                -Title ("Test ticket {0}" -f $now.ToString("HH:mm")) `
                -Description "Test ticket created from the UI." `
                -Category "Testing" `
                -Priority "Low" | Out-Null
        }
        catch {
            Write-Warning "Tickets UI: failed to create test ticket. $_"
        }

        Update-QOTicketsGrid
    })

    # Double-click a row to rename the ticket TITLE
    $TicketsGrid.Add_MouseDoubleClick({
        param($sender, $args)

        $row = $sender.SelectedItem
        if (-not $row) { return }

        # Use a simple input box for now
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

        $currentTitle = $row.Title
        $promptText   = "Enter a new title for this ticket:"
        $promptTitle  = "Rename ticket"

        $newTitle = [Microsoft.VisualBasic.Interaction]::InputBox(
            $promptText,
            $promptTitle,
            $currentTitle
        )

        if ([string]::IsNullOrWhiteSpace($newTitle)) { return }

        # For now, update in-memory; later we can wire this to persist into the JSON store.
        $row.Title = $newTitle
        $script:TicketsGrid.Items.Refresh()
    })

    # Initial load
    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid
