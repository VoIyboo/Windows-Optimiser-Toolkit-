# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"   -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

$script:TicketsColumnLayoutApplying = $false
$script:TicketsGrid                 = $null

# -------------------------------------------------------------------
# Column layout helpers
# -------------------------------------------------------------------

function Get-QOTicketsColumnLayout {
    (Get-QOSettings).TicketsColumnLayout
}

function Save-QOTicketsColumnLayout {
    param(
        [Parameter(Mandatory)]
        $DataGrid
    )

    if ($script:TicketsColumnLayoutApplying) { return }

    $settings = Get-QOSettings

    $settings.TicketsColumnLayout = @(
        $DataGrid.Columns |
        Sort-Object DisplayIndex |
        ForEach-Object {
            [pscustomobject]@{
                Header       = $_.Header.ToString()
                DisplayIndex = $_.DisplayIndex
                Width        = if ($_.Width -is [double]) { [double]$_.Width } else { $null }
            }
        }
    )

    Save-QOSettings -Settings $settings
}

function Apply-QOTicketsColumnLayout {
    param(
        [Parameter(Mandatory)]
        $DataGrid
    )

    $layout = Get-QOTicketsColumnLayout
    if (-not $layout -or $layout.Count -eq 0) { return }

    $script:TicketsColumnLayoutApplying = $true
    try {
        foreach ($entry in $layout) {
            $header = $entry.Header
            if (-not $header) { continue }

            $col = $DataGrid.Columns |
                Where-Object { $_.Header.ToString() -eq $header } |
                Select-Object -First 1

            if (-not $col) { continue }

            if ($entry.DisplayIndex -ne $null -and $entry.DisplayIndex -ge 0) {
                $col.DisplayIndex = $entry.DisplayIndex
            }

            if ($entry.Width -ne $null -and $entry.Width -gt 0) {
                $col.Width = [double]$entry.Width
            }
        }
    }
    finally {
        $script:TicketsColumnLayoutApplying = $false
    }
}

# Backwards-compat wrapper for any older code
function Apply-QOTicketsColumnOrder {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid
    )

    Apply-QOTicketsColumnLayout -DataGrid $TicketsGrid
}

# -------------------------------------------------------------------
# Grid data binding
# -------------------------------------------------------------------

function Update-QOTicketsGrid {

    if (-not $script:TicketsGrid) { return }

    try {
        $db = Get-QOTickets
        $tickets = if ($db -and $db.Tickets) { @($db.Tickets) } else { @() }
    }
    catch {
        Write-Warning "Tickets UI: failed to load tickets. $_"
        $tickets = @()
    }

    $view = foreach ($t in $tickets) {

        # Normalise CreatedAt
        $raw     = $t.CreatedAt
        $created = $null

        if ($raw -is [datetime]) {
            $created = $raw
        }
        elseif ($raw) {
            [datetime]::TryParse($raw, [ref]$created) | Out-Null
        }

        $createdString = if ($created) {
            $created.ToString('dd/MM/yyyy h:mm tt')
        } else {
            $raw
        }

        [PSCustomObject]@{
            Title     = $t.Title
            CreatedAt = $createdString
            Status    = $t.Status
            Priority  = $t.Priority
            Id        = $t.Id
            Category  = $t.Category
        }
    }

    # Force $view to ALWAYS be an array (even with 0 or 1 tickets)
    if ($view -isnot [System.Collections.IEnumerable] -or $view -is [string]) {
        $view = @($view)
    } else {
        $view = @($view)
    }

    # Bind to the grid
    $script:TicketsGrid.ItemsSource = $view
}

# -------------------------------------------------------------------
# Initialise Tickets tab UI
# -------------------------------------------------------------------

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid,

        [Parameter(Mandatory)]
        $BtnRefreshTickets,

        [Parameter(Mandatory)]
        $BtnNewTicket
        
        [Parameter(Mandatory)]
        $BtnDeleteTicket
    )

    # Keep reference
    $script:TicketsGrid = $TicketsGrid

    # Allow inline editing (Title column editable in XAML)
    $TicketsGrid.IsReadOnly            = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true

    # Apply saved layout when grid is loaded
    $TicketsGrid.Add_Loaded({
        Apply-QOTicketsColumnLayout -DataGrid $script:TicketsGrid
        Update-QOTicketsGrid
    })

    # Save layout when columns are reordered
    $TicketsGrid.Add_ColumnReordered({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) {
            Save-QOTicketsColumnLayout -DataGrid $sender
        }
    })

    # NO ColumnWidthChanged here; WPF DataGrid does not expose it in this context.

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

    # Initial load of data
    Update-QOTicketsGrid
}

Export-ModuleMember -Function `
    Initialize-QOTicketsUI, `
    Update-QOTicketsGrid
