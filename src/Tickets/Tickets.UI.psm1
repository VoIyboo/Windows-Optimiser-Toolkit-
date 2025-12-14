# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction Stop

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
                $col.DisplayIndex = [int]$entry.DisplayIndex
            }

            if ($entry.Width -ne $null -and [double]$entry.Width -gt 0) {
                $col.Width = [double]$entry.Width
            }
        }
    }
    finally {
        $script:TicketsColumnLayoutApplying = $false
    }
}

# Backwards compat name
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

    $rows = foreach ($t in $tickets) {

        $rawCreated = $t.CreatedAt
        $created    = $null

        if ($rawCreated -is [datetime]) {
            $created = $rawCreated
        }
        elseif ($rawCreated) {
            [datetime]::TryParse([string]$rawCreated, [ref]$created) | Out-Null
        }

        $createdString = if ($created) { $created.ToString('dd/MM/yyyy h:mm tt') } else { [string]$rawCreated }

        [pscustomobject]@{
            Title     = [string]$t.Title
            CreatedAt = $createdString
            Status    = [string]$t.Status
            Priority  = [string]$t.Priority
            Category  = [string]$t.Category
            Id        = [string]$t.Id
        }
    }

    # Always bind an array, even for 0 or 1 items
    $script:TicketsGrid.ItemsSource = @($rows)
}

# -------------------------------------------------------------------
# Initialise Tickets tab UI
# -------------------------------------------------------------------

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory = $true)]
        [object]$TicketsGrid,

        [Parameter(Mandatory = $true)]
        [object]$BtnRefreshTickets,

        [Parameter(Mandatory = $true)]
        [object]$BtnNewTicket,

        [Parameter(Mandatory = $false)]
        [object]$BtnDeleteTicket
    )

    $script:TicketsGrid = $TicketsGrid

    $TicketsGrid.IsReadOnly            = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true

    $TicketsGrid.Add_Loaded({
        Apply-QOTicketsColumnLayout -DataGrid $script:TicketsGrid
        Update-QOTicketsGrid
    })

    $TicketsGrid.Add_ColumnReordered({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) {
            Save-QOTicketsColumnLayout -DataGrid $sender
        }
    })

    $BtnRefreshTickets.Add_Click({
        Update-QOTicketsGrid
    })

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

   if ($BtnDeleteTicket) {
    $BtnDeleteTicket.Add_Click({
        try {
            $selectedItems = $script:TicketsGrid.SelectedItems

            if (-not $selectedItems -or $selectedItems.Count -lt 1) {
                return
            }

            $idsToDelete = @()

            foreach ($item in $selectedItems) {
                if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'Id') {
                    if (-not [string]::IsNullOrWhiteSpace($item.Id)) {
                        $idsToDelete += [string]$item.Id
                    }
                }
            }

            $idsToDelete = $idsToDelete | Select-Object -Unique

            if ($idsToDelete.Count -lt 1) {
                return
            }

            foreach ($id in $idsToDelete) {
                Remove-QOTicket -Id $id | Out-Null
            }
        }
        catch {
            Write-Warning "Tickets UI: failed to delete ticket(s). $_"
        }

        Update-QOTicketsGrid
    })
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid
