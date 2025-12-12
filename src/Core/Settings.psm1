# Tickets.UI.psm1
# Simple UI wiring for the Tickets tab

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"   -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction SilentlyContinue

# Guard so we do not re-save while we are applying the saved layout
$script:TicketsColumnLayoutApplying = $false

function Get-QOTicketsColumnLayout {
    $settings = Get-QOSettings
    return $settings.TicketsColumnLayout
}

function Save-QOTicketsColumnLayout {
    param(
        [Parameter(Mandatory)]
        $DataGrid
    )

    if ($script:TicketsColumnLayoutApplying) { return }

    $settings = Get-QOSettings

    # Capture current columns by their DisplayIndex and header name + width
    $layout = @(
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

    $settings.TicketsColumnLayout = $layout
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

            if ($entry.DisplayIndex -ge 0) {
                $col.DisplayIndex = $entry.DisplayIndex
            }

            if ($entry.Width -and $entry.Width -gt 0) {
                $col.Width = [double]$entry.Width
            }
        }
    }
    finally {
        $script:TicketsColumnLayoutApplying = $false
    }
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
            Title     = $t.Title
            CreatedAt = $createdString
            Status    = $t.Status
            Priority  = $t.Priority
            Id        = $t.Id
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

    # Keep reference
    $script:TicketsGrid = $TicketsGrid

    # Allow inline editing (Title column is editable in XAML)
    $TicketsGrid.IsReadOnly           = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true

    # Apply saved layout once the grid is loaded
    $TicketsGrid.Add_Loaded({
        Apply-QOTicketsColumnLayout -DataGrid $script:TicketsGrid
    })

    # Save layout whenever columns are reordered
    $TicketsGrid.Add_ColumnReordered({
        param($sender,$eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) {
            Save-QOTicketsColumnLayout -DataGrid $sender
        }
    })

    # Save layout whenever a column width is changed
    $TicketsGrid.Add_ColumnWidthChanged({
        param($sender,$eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) {
            Save-QOTicketsColumnLayout -DataGrid $sender
        }
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

    # Initial load of data
    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid


# ------------------------------
# Quinn Optimiser Toolkit Settings helpers
# ------------------------------

# Where settings.json will live
$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QOSettings {
    if (-not (Test-Path $script:QOSettingsPath)) {
        # First run: create a default settings object
        $default = [PSCustomObject]@{
            TicketsColumnLayout = @()
        }

        $dir = Split-Path $script:QOSettingsPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $default | ConvertTo-Json -Depth 5 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $default
    }

    $json = Get-Content -Path $script:QOSettingsPath -Raw -ErrorAction SilentlyContinue
    if (-not $json) {
        return [PSCustomObject]@{
            TicketsColumnLayout = @()
        }
    }

    $settings = $json | ConvertFrom-Json

    # Make sure TicketsColumnLayout always exists
    if (-not $settings.PSObject.Properties.Name -contains 'TicketsColumnLayout') {
        $settings | Add-Member -NotePropertyName TicketsColumnLayout -NotePropertyValue @()
    }

    return $settings
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $dir = Split-Path $script:QOSettingsPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 5 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
}

# ============================================================
# Quinn Optimiser Toolkit - Global Settings helpers
# ============================================================

# Path for settings.json used across the toolkit
$script:QOSettingsPath = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Settings.json"

function Get-QOSettings {
    if (-not (Test-Path $script:QOSettingsPath)) {
        # First run: create a default settings object
        $default = [PSCustomObject]@{
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }

        $dir = Split-Path $script:QOSettingsPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $default | ConvertTo-Json -Depth 6 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
        return $default
    }

    $json = Get-Content -Path $script:QOSettingsPath -Raw -ErrorAction SilentlyContinue
    if (-not $json) {
        return [PSCustomObject]@{
            TicketsColumnLayout   = @()
            TicketStorePath       = $null
            LocalTicketBackupPath = $null
        }
    }

    $settings = $json | ConvertFrom-Json

    if (-not $settings.PSObject.Properties.Name -contains 'TicketsColumnLayout') {
        $settings | Add-Member -NotePropertyName TicketsColumnLayout -NotePropertyValue @()
    }
    if (-not $settings.PSObject.Properties.Name -contains 'TicketStorePath') {
        $settings | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $null
    }
    if (-not $settings.PSObject.Properties.Name -contains 'LocalTicketBackupPath') {
        $settings | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue $null
    }

    return $settings
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $dir = Split-Path $script:QOSettingsPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 6 | Set-Content -Path $script:QOSettingsPath -Encoding UTF8
}
