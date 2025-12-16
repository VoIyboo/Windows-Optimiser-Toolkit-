# Tickets.UI.psm1
# UI wiring for the Tickets tab (with toggleable row details)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction Stop

# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------
$script:TicketsColumnLayoutApplying = $false
$script:TicketsGrid                 = $null

# -------------------------------------------------------------------
# Column layout helpers (order + width)
# -------------------------------------------------------------------
function Get-QOTicketsColumnLayout {
    $s = Get-QOSettings
    return $s.TicketsColumnLayout
}

function Save-QOTicketsColumnLayout {
    param([Parameter(Mandatory)] $DataGrid)

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
    param([Parameter(Mandatory)] $DataGrid)

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
    param([Parameter(Mandatory)] $TicketsGrid)
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
            Title       = [string]$t.Title
            CreatedAt   = $createdString
            Status      = [string]$t.Status
            Priority    = [string]$t.Priority
            Category    = [string]$t.Category
            Description = [string]$t.Description
            Id          = [string]$t.Id
        }
    }

    $script:TicketsGrid.ItemsSource = @($rows)
}

function Select-QOTicketRowById {
    param([Parameter(Mandatory)] [string]$Id)

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
# Details view (RowDetailsTemplate + toggle)
# -------------------------------------------------------------------
function Ensure-QOTicketsRowDetails {
    param([Parameter(Mandatory)] $Grid)

    if (-not $Grid.RowDetailsTemplate) {

        $xaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
    <Border Margin="10,8,10,8"
            Padding="10"
            CornerRadius="6"
            BorderThickness="1"
            BorderBrush="#374151"
            Background="#020617">

        <DockPanel LastChildFill="True">

            <TextBlock DockPanel.Dock="Top"
                       Text="Email body"
                       Foreground="White"
                       FontSize="14"
                       FontWeight="SemiBold"
                       Margin="0,0,0,8"/>

            <ScrollViewer VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">

                <TextBlock Text="{Binding Description}"
                           Foreground="White"
                           TextWrapping="Wrap"
                           FontSize="12"/>

            </ScrollViewer>

        </DockPanel>
    </Border>
</DataTemplate>
"@


        $sr = New-Object System.IO.StringReader($xaml)
        $xr = New-Object System.Xml.XmlTextReader($sr)
        $template = [System.Windows.Markup.XamlReader]::Load($xr)
        $Grid.RowDetailsTemplate = $template
    }

    # Do not auto open on selection
    $Grid.RowDetailsVisibilityMode = [System.Windows.Controls.DataGridRowDetailsVisibilityMode]::Collapsed
}

function Toggle-QOTicketDetailsForItem {
    param(
        [Parameter(Mandatory)] $Grid,
        [Parameter(Mandatory)] $Item
    )

    if (-not $Item) { return }

    $row = $Grid.ItemContainerGenerator.ContainerFromItem($Item)
    if (-not $row) {
        $Grid.UpdateLayout()
        $Grid.ScrollIntoView($Item)
        $row = $Grid.ItemContainerGenerator.ContainerFromItem($Item)
    }
    if (-not $row) { return }

    $current = $row.DetailsVisibility
    if ($current -eq [System.Windows.Visibility]::Visible) {
        $row.DetailsVisibility = [System.Windows.Visibility]::Collapsed
    }
    else {
        $row.DetailsVisibility = [System.Windows.Visibility]::Visible
    }
}

function Ensure-QOTicketsActionsColumn {
    param([Parameter(Mandatory)] $Grid)

    $already = $false
    foreach ($c in @($Grid.Columns)) {
        if ($c -and $c.Header -and $c.Header.ToString() -eq "Actions") {
            $already = $true
            break
        }
    }
    if ($already) { return }

    $templateXaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
    <Button Content="View" Padding="10,4" MinWidth="70" Tag="{Binding}">
        <Button.Style>
            <Style TargetType="Button">
                <Setter Property="Background" Value="#2563EB"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="BorderBrush" Value="#1E3A8A"/>
                <Setter Property="BorderThickness" Value="0"/>
            </Style>
        </Button.Style>
    </Button>
</DataTemplate>
"@

    $sr = New-Object System.IO.StringReader($templateXaml)
    $xr = New-Object System.Xml.XmlTextReader($sr)
    $cellTemplate = [System.Windows.Markup.XamlReader]::Load($xr)

    $col = New-Object System.Windows.Controls.DataGridTemplateColumn
    $col.Header = "Actions"
    $col.CellTemplate = $cellTemplate
    $col.Width = New-Object System.Windows.Controls.DataGridLength(90)

    [void]$Grid.Columns.Add($col)
}

function Wire-QOTicketsActionsClick {
    param([Parameter(Mandatory)] $Grid)

    # Only wire once
    if ($Grid.Tag -eq "QOT_ACTIONS_WIRED") { return }
    $Grid.Tag = "QOT_ACTIONS_WIRED"

    $Grid.AddHandler(
        [System.Windows.Controls.Button]::ClickEvent,
        [System.Windows.RoutedEventHandler]{
            param($sender, $e)

            $btn = $e.OriginalSource
            if (-not ($btn -is [System.Windows.Controls.Button])) { return }
            if ($btn.Content -ne "View") { return }

            $item = $btn.Tag
            if (-not $item) { return }

            # Keep selection in sync
            $script:TicketsGrid.SelectedItem = $item
            Toggle-QOTicketDetailsForItem -Grid $script:TicketsGrid -Item $item

            $e.Handled = $true
        }
    )
}

# -------------------------------------------------------------------
# Init
# -------------------------------------------------------------------
function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)] $TicketsGrid,
        [Parameter(Mandatory)] $BtnRefreshTickets,
        [Parameter(Mandatory)] $BtnNewTicket,
        [Parameter(Mandatory = $false)] $BtnDeleteTicket
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $script:TicketsGrid = $TicketsGrid

    # Grid behaviour
    $TicketsGrid.IsReadOnly            = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true

    try {
        $TicketsGrid.SelectionUnit = "FullRow"
        $TicketsGrid.SelectionMode = "Extended"
    } catch { }

    Ensure-QOTicketsRowDetails -Grid $TicketsGrid
    Ensure-QOTicketsActionsColumn -Grid $TicketsGrid
    Wire-QOTicketsActionsClick -Grid $TicketsGrid

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
