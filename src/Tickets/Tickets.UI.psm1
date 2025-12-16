# Tickets.UI.psm1
# UI wiring for the Tickets tab (with View action + RowDetails)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction Stop

# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

$script:TicketsColumnLayoutApplying = $false
$script:TicketsGrid                 = $null
$script:TicketsUIHandlersHooked     = $false

# -------------------------------------------------------------------
# Column layout helpers (order + width)
# -------------------------------------------------------------------

function Get-QOTicketsColumnLayout {
    $s = Get-QOSettings
    return $s.TicketsColumnLayout
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
            $widthValue = $null
            try {
                if ($_.Width -and $_.Width.IsAbsolute) {
                    $widthValue = [double]$_.Width.Value
                }
            } catch { }

            [pscustomobject]@{
                Header       = $_.Header.ToString()
                DisplayIndex = $_.DisplayIndex
                Width        = $widthValue
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

            if ($entry.DisplayIndex -ne $null -and [int]$entry.DisplayIndex -ge 0) {
                $col.DisplayIndex = [int]$entry.DisplayIndex
            }

            if ($entry.Width -ne $null -and [double]$entry.Width -gt 0) {
                $col.Width = New-Object System.Windows.Controls.DataGridLength([double]$entry.Width)
            }
        }
    }
    finally {
        $script:TicketsColumnLayoutApplying = $false
    }
}

function Apply-QOTicketsColumnOrder {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid
    )
    Apply-QOTicketsColumnLayout -DataGrid $TicketsGrid
}

# -------------------------------------------------------------------
# View action + RowDetails
# -------------------------------------------------------------------

function Ensure-QOTTicketsRowDetails {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid
    )

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
    } catch { }

    if (-not $TicketsGrid) { return }

    if ($TicketsGrid.RowDetailsTemplate) { return }

    $detailsXaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Border Margin="8,4,8,10" Padding="10" CornerRadius="6" Background="#020617" BorderBrush="#374151" BorderThickness="1">
        <StackPanel>
            <TextBlock Text="Ticket details" Foreground="White" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="120"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="Title:" Foreground="#9CA3AF" Margin="0,0,8,4"/>
                <TextBlock Grid.Row="0" Grid.Column="1" Text="{Binding Title}" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,4"/>

                <TextBlock Grid.Row="1" Grid.Column="0" Text="Created:" Foreground="#9CA3AF" Margin="0,0,8,4"/>
                <TextBlock Grid.Row="1" Grid.Column="1" Text="{Binding CreatedAt}" Foreground="White" Margin="0,0,0,4"/>

                <TextBlock Grid.Row="2" Grid.Column="0" Text="Status:" Foreground="#9CA3AF" Margin="0,0,8,4"/>
                <TextBlock Grid.Row="2" Grid.Column="1" Text="{Binding Status}" Foreground="White" Margin="0,0,0,4"/>

                <TextBlock Grid.Row="3" Grid.Column="0" Text="Priority:" Foreground="#9CA3AF" Margin="0,0,8,4"/>
                <TextBlock Grid.Row="3" Grid.Column="1" Text="{Binding Priority}" Foreground="White" Margin="0,0,0,4"/>

                <TextBlock Grid.Row="4" Grid.Column="0" Text="Category:" Foreground="#9CA3AF" Margin="0,0,8,0"/>
                <TextBlock Grid.Row="4" Grid.Column="1" Text="{Binding Category}" Foreground="White"/>
            </Grid>

            <Border Margin="0,10,0,0" Padding="8" CornerRadius="6" Background="#0F172A" BorderBrush="#374151" BorderThickness="1">
                <TextBlock Text="Email body and thread view comes next. This panel is the foundation."
                           Foreground="#9CA3AF" TextWrapping="Wrap"/>
            </Border>
        </StackPanel>
    </Border>
</DataTemplate>
"@

    try {
        $xml = [xml]$detailsXaml
        $reader = New-Object System.Xml.XmlNodeReader $xml
        $template = [System.Windows.Markup.XamlReader]::Load($reader)
        $TicketsGrid.RowDetailsTemplate = $template
        $TicketsGrid.RowDetailsVisibilityMode = "VisibleWhenSelected"
    } catch {
        Write-Warning "Tickets UI: failed to set RowDetailsTemplate. $_"
    }
}

function Ensure-QOTTicketsActionsColumn {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid
    )

    if (-not $TicketsGrid) { return }

    # Already present
    foreach ($c in @($TicketsGrid.Columns)) {
        if ($c -and $c.Header -and $c.Header.ToString() -eq "Actions") { return }
    }

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
    } catch { }

    $cellTemplateXaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Button Name="BtnViewTicket"
            Content="View"
            Padding="10,4"
            Margin="4,0,4,0"
            Tag="{Binding Id}"/>
</DataTemplate>
"@

    try {
        $xml = [xml]$cellTemplateXaml
        $reader = New-Object System.Xml.XmlNodeReader $xml
        $cellTemplate = [System.Windows.Markup.XamlReader]::Load($reader)

        $col = New-Object System.Windows.Controls.DataGridTemplateColumn
        $col.Header = "Actions"
        $col.CellTemplate = $cellTemplate
        $col.CanUserReorder = $true
        $col.CanUserResize = $true
        $col.IsReadOnly = $true
        $col.Width = New-Object System.Windows.Controls.DataGridLength(90)

        [void]$TicketsGrid.Columns.Add($col)
    } catch {
        Write-Warning "Tickets UI: failed to add Actions column. $_"
    }
}

function Hook-QOTTicketsViewHandler {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid
    )

    if (-not $TicketsGrid) { return }
    if ($script:TicketsUIHandlersHooked) { return }

    $script:TicketsUIHandlersHooked = $true

    # Catch clicks on the View button inside the DataGrid
    $TicketsGrid.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]{
            param($sender, $e)

            try {
                $btn = $e.OriginalSource -as [System.Windows.Controls.Button]
                if (-not $btn) { return }
                if ($btn.Name -ne "BtnViewTicket") { return }

                $id = "$($btn.Tag)".Trim()
                if ([string]::IsNullOrWhiteSpace($id)) { return }

                Select-QOTicketRowById -Id $id

                # If already selected, nudge the details refresh
                try { $sender.UpdateLayout() | Out-Null } catch { }
            } catch { }
        }
    )
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

        $createdString = if ($created) {
            $created.ToString('dd/MM/yyyy h:mm tt')
        }
        else {
            [string]$rawCreated
        }

        [pscustomobject]@{
            Title     = [string]$t.Title
            CreatedAt = $createdString
            Status    = [string]$t.Status
            Priority  = [string]$t.Priority
            Category  = [string]$t.Category
            Id        = [string]$t.Id
        }
    }

    $script:TicketsGrid.ItemsSource = @($rows)
}

function Select-QOTicketRowById {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    if (-not $script:TicketsGrid) { return }
    if ([string]::IsNullOrWhiteSpace($Id)) { return }

    $match = $null
    foreach ($item in $script:TicketsGrid.Items) {
        if ($null -eq $item) { continue }
        if ($item.PSObject.Properties.Name -contains "Id") {
            if ([string]$item.Id -eq $Id) { $match = $item; break }
        }
    }

    if ($match) {
        $script:TicketsGrid.SelectedItem = $match
        $script:TicketsGrid.ScrollIntoView($match) | Out-Null
    }
}

# -------------------------------------------------------------------
# Init
# -------------------------------------------------------------------

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)]
        $TicketsGrid,

        [Parameter(Mandatory)]
        $BtnRefreshTickets,

        [Parameter(Mandatory)]
        $BtnNewTicket,

        [Parameter(Mandatory = $false)]
        $BtnDeleteTicket
    )

    $script:TicketsGrid = $TicketsGrid

    # Grid behaviour
    $TicketsGrid.IsReadOnly            = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true

    # Multi select
    try {
        $TicketsGrid.SelectionUnit = "FullRow"
        $TicketsGrid.SelectionMode = "Extended"
    } catch { }

    # Add View + RowDetails
    Ensure-QOTTicketsActionsColumn -TicketsGrid $TicketsGrid
    Ensure-QOTTicketsRowDetails    -TicketsGrid $TicketsGrid
    Hook-QOTTicketsViewHandler     -TicketsGrid $TicketsGrid

    # Apply saved layout once the grid is loaded
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

    # Save layout when a column DisplayIndex changes
    $TicketsGrid.Add_ColumnDisplayIndexChanged({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) {
            Save-QOTicketsColumnLayout -DataGrid $sender
        }
    })

    # Refresh (poll email first if available)
    $BtnRefreshTickets.Add_Click({
        try {
            if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                Invoke-QOEmailTicketPoll | Out-Null
            }
        } catch { }

        Update-QOTicketsGrid
    })

    # Delete (supports multi select)
    if ($BtnDeleteTicket) {

        $BtnDeleteTicket.Add_Click({
            try {
                $selectedItems = @($script:TicketsGrid.SelectedItems)
                if (-not $selectedItems -or $selectedItems.Count -lt 1) { return }

                $idsToDelete = @(
                    foreach ($item in $selectedItems) {
                        if ($null -ne $item -and ($item.PSObject.Properties.Name -contains 'Id')) {
                            if (-not [string]::IsNullOrWhiteSpace($item.Id)) { [string]$item.Id }
                        }
                    }
                ) | Select-Object -Unique

                if (-not $idsToDelete -or $idsToDelete.Count -lt 1) { return }

                foreach ($id in $idsToDelete) {
                    if (Get-Command Remove-QOTicket -ErrorAction SilentlyContinue) {
                        Remove-QOTicket -Id $id | Out-Null
                    }
                }
            }
            catch {
                Write-Warning "Tickets UI: failed to delete ticket(s). $_"
            }

            Update-QOTicketsGrid
        })
    }

    # New test ticket
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

    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid, Apply-QOTicketsColumnOrder
