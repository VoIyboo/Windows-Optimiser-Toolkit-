# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1" -Force -ErrorAction SilentlyContinue

function Update-QOTicketsGrid {
    try {
        $db = Get-QOTickets
    }
    catch {
        Write-Warning "Tickets UI: failed to load tickets. $_"
        $db = $null
    }

    $tickets = @()
    if ($db -and $db.Tickets) {
        $tickets = @($db.Tickets)
    }

    # Build view objects with formatted CreatedAt
    $view = foreach ($t in $tickets) {

        $created = $null
        $raw     = $null

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
            # Example: 12/12/2025 8:45 PM  (no seconds)
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

            $ticket = New-QOTicket `
                -Title ("Test ticket {0}" -f $now.ToString("HH:mm")) `
                -Description "Test ticket created from the UI." `
                -Category "Testing" `
                -Priority "Low"

            Add-QOTicket -Ticket $ticket | Out-Null
        }
        catch {
            Write-Warning "Tickets UI: failed to create test ticket. $_"
        }

        Update-QOTicketsGrid
    })

    # Inline edit: when a cell edit is committed, persist Title changes
    $TicketsGrid.Add_CellEditEnding({
        param($sender, $e)

        if ($e.EditAction -ne [System.Windows.Controls.DataGridEditAction]::Commit) {
            return
        }

        $rowObj = $e.Row.Item
        if (-not $rowObj) { return }

        # Only care about the Title column
        if ($e.Column -and $e.Column.Header -ne 'Title') {
            return
        }

        $newTitle = $rowObj.Title
        if ([string]::IsNullOrWhiteSpace($newTitle)) {
            return
        }

        try {
            Set-QOTicketTitle -Id $rowObj.Id -Title $newTitle | Out-Null
        }
        catch {
            Write-Warning "Tickets UI: failed to rename ticket. $_"
        }

        # Refresh grid so formatting stays consistent
        Update-QOTicketsGrid
    })

    # Initial load
    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid
