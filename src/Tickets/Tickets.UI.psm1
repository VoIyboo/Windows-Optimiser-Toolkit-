# Tickets.UI.psm1
# UI wiring for the Tickets tab (RowDetails email body viewer)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\Core\Settings.psm1" -Force -ErrorAction Stop

# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------
$script:TicketsColumnLayoutApplying = $false
$script:TicketsGrid                 = $null

# Track which ticket IDs are expanded
$script:ExpandedTicketIds = New-Object 'System.Collections.Generic.HashSet[string]'

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
# Helpers
# -------------------------------------------------------------------
function Get-QOTicketBodyText {
    param([Parameter(Mandatory)] $Ticket)

    foreach ($name in @('EmailBody', 'Body', 'Description', 'RawBody', 'PlainTextBody')) {
        if ($Ticket.PSObject.Properties.Name -contains $name) {
            $val = $Ticket.$name
            if ($val) { return [string]$val }
        }
    }
    return ""
}

function Get-RowItemIdSafe {
    param($RowItem)
    if ($null -eq $RowItem) { return $null }
    if ($RowItem.PSObject.Properties.Name -contains 'Id') {
        $id = [string]$RowItem.Id
        if (-not [string]::IsNullOrWhiteSpace($id)) { return $id }
    }
    return $null
}

function Set-RowDetailsState {
    param(
        [Parameter(Mandatory)] [System.Windows.Controls.DataGridRow] $Row,
        [Parameter(Mandatory)] [bool] $Expanded
    )
    try {
        $Row.DetailsVisibility = if ($Expanded) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    } catch { }
}

function Toggle-TicketRowDetails {
    param([Parameter(Mandatory)] $RowItem)

    $id = Get-RowItemIdSafe -RowItem $RowItem
    if (-not $id) { return }

    if ($script:ExpandedTicketIds.Contains($id)) {
        [void]$script:ExpandedTicketIds.Remove($id)
    } else {
        [void]$script:ExpandedTicketIds.Add($id)
    }

    try {
        $row = $script:TicketsGrid.ItemContainerGenerator.ContainerFromItem($RowItem)
        if ($row -is [System.Windows.Controls.DataGridRow]) {
            $expanded = $script:ExpandedTicketIds.Contains($id)
            Set-RowDetailsState -Row $row -Expanded $expanded
        }
    } catch { }
}

function Expand-AllTicketDetails {
    if (-not $script:TicketsGrid) { return }
    foreach ($item in @($script:TicketsGrid.Items)) {
        $id = Get-RowItemIdSafe -RowItem $item
        if ($id) { [void]$script:ExpandedTicketIds.Add($id) }
    }
    try {
        foreach ($item in @($script:TicketsGrid.Items)) {
            $row = $script:TicketsGrid.ItemContainerGenerator.ContainerFromItem($item)
            if ($row -is [System.Windows.Controls.DataGridRow]) { Set-RowDetailsState -Row $row -Expanded $true }
        }
    } catch { }
}

function Collapse-AllTicketDetails {
    if (-not $script:TicketsGrid) { return }
    $script:ExpandedTicketIds.Clear() | Out-Null
    try {
        foreach ($item in @($script:TicketsGrid.Items)) {
            $row = $script:TicketsGrid.ItemContainerGenerator.ContainerFromItem($item)
            if ($row -is [System.Windows.Controls.DataGridRow]) { Set-RowDetailsState -Row $row -Expanded $false }
        }
    } catch { }
}

# Adds an expander arrow column at the far right (▸ / ▾)
function Ensure-QOTicketsExpanderColumn {
    param([Parameter(Mandatory)] $Grid)

    $existing = $Grid.Columns | Where-Object { [string]$_.Header -eq " " } | Select-Object -First 1
    if ($existing) { return }

    $xaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Button Width="28" Height="22" Padding="0" Margin="2" Focusable="False"
          Tag="{Binding RelativeSource={RelativeSource AncestorType=DataGridRow}}">
    <TextBlock HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="14" Foreground="White">
      <TextBlock.Style>
        <Style TargetType="{x:Type TextBlock}">
          <Setter Property="Text" Value="▸"/>
          <Style.Triggers>
            <DataTrigger Binding="{Binding RelativeSource={RelativeSource AncestorType=DataGridRow}, Path=DetailsVisibility}" Value="Visible">
              <Setter Property="Text" Value="▾"/>
            </DataTrigger>
          </Style.Triggers>
        </Style>
      </TextBlock.Style>
    </TextBlock>
  </Button>
</DataTemplate>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $template = [System.Windows.Markup.XamlReader]::Load($reader)

    $col = New-Object System.Windows.Controls.DataGridTemplateColumn
    $col.Header = " "
    $col.Width  = New-Object System.Windows.Controls.DataGridLength(34)
    $col.CanUserReorder = $false
    $col.CanUserResize  = $false
    $col.CellTemplate   = $template

    [void]$Grid.Columns.Add($col)
}

function Wire-QOTicketsExpanderClicks {
    param([Parameter(Mandatory)] $Grid)

    $Grid.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]{
            param($sender, $e)
            try {
                $btn = $e.OriginalSource -as [System.Windows.Controls.Button]
                if (-not $btn) { return }

                $row = $btn.Tag -as [System.Windows.Controls.DataGridRow]
                if (-not $row) { return }

                Toggle-TicketRowDetails -RowItem $row.Item
                $e.Handled = $true
            } catch { }
        },
        $true
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

        if ($rawCreated -is [datetime]) { $created = $rawCreated }
        elseif ($rawCreated) { [datetime]::TryParse([string]$rawCreated, [ref]$created) | Out-Null }

        $createdString = if ($created) { $created.ToString('dd/MM/yyyy h:mm tt') } else { [string]$rawCreated }

        [pscustomobject]@{
            Title     = [string]$t.Title
            CreatedAt = $createdString
            Status    = [string]$t.Status
            Priority  = [string]$t.Priority
            Id        = [string]$t.Id
            EmailBody = (Get-QOTicketBodyText -Ticket $t)
        }
    }

    $script:TicketsGrid.ItemsSource = @($rows)
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

    $script:TicketsGrid = $TicketsGrid

    # Ticket list behaviour (not editable)
    $TicketsGrid.IsReadOnly            = $true
    $TicketsGrid.CanUserAddRows        = $false
    $TicketsGrid.CanUserDeleteRows     = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true
    $TicketsGrid.SelectionUnit         = "FullRow"
    $TicketsGrid.SelectionMode         = "Extended"

    # No horizontal scrolling on the grid itself
    try { $TicketsGrid.HorizontalScrollBarVisibility = 'Disabled' } catch { }

    # RowDetails default collapsed
    try { $TicketsGrid.RowDetailsVisibilityMode = 'Collapsed' } catch { }

    Ensure-QOTicketsExpanderColumn -Grid $TicketsGrid
    Wire-QOTicketsExpanderClicks   -Grid $TicketsGrid

    # RowDetailsTemplate: wrap to width, no left-right scroll, cap height 240
    $rowDetailsXaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
  <Border Margin="10,4,10,10"
          CornerRadius="6"
          BorderThickness="1"
          BorderBrush="#374151"
          Background="#020617"
          Padding="10"
          HorizontalAlignment="Stretch">
    <TextBox Text="{Binding EmailBody}"
             IsReadOnly="True"
             Background="Transparent"
             BorderThickness="0"
             Foreground="White"
             TextWrapping="Wrap"
             AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto"
             HorizontalScrollBarVisibility="Disabled"
             MaxHeight="240"
             HorizontalAlignment="Stretch"/>
  </Border>
</DataTemplate>
"@

    try {
        $sr = New-Object System.IO.StringReader $rowDetailsXaml
        $xr = [System.Xml.XmlReader]::Create($sr)
        $TicketsGrid.RowDetailsTemplate = [System.Windows.Markup.XamlReader]::Load($xr)
    } catch {
        Write-Warning "Tickets UI: failed to apply RowDetailsTemplate. $_"
    }

    $TicketsGrid.Add_Loaded({
        Apply-QOTicketsColumnLayout -DataGrid $script:TicketsGrid
        Update-QOTicketsGrid
    })

    $TicketsGrid.Add_ColumnReordered({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) { Save-QOTicketsColumnLayout -DataGrid $sender }
    })

    $TicketsGrid.Add_ColumnDisplayIndexChanged({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) { Save-QOTicketsColumnLayout -DataGrid $sender }
    })
    # Save when user resizes columns (dragging header dividers)
    $TicketsGrid.AddHandler(
        [System.Windows.Controls.DataGrid]::ColumnWidthChangedEvent,
        [System.Windows.RoutedEventHandler]{
            param($sender, $e)
            try {
                if (-not $script:TicketsColumnLayoutApplying) {
                    Save-QOTicketsColumnLayout -DataGrid $sender
                }
            } catch { }
        },
        $true
    )




    # Keep details state correct when rows are realised
    $TicketsGrid.Add_LoadingRow({
        param($sender, $e)
        try {
            $item = $e.Row.Item
            $id = Get-RowItemIdSafe -RowItem $item
            if ($id) {
                $expanded = $script:ExpandedTicketIds.Contains($id)
                Set-RowDetailsState -Row $e.Row -Expanded $expanded
            }
        } catch { }
    })

    # Double click row toggles details
    $TicketsGrid.Add_MouseDoubleClick({
        try {
            $item = $script:TicketsGrid.SelectedItem
            if ($item) { Toggle-TicketRowDetails -RowItem $item }
        } catch { }
    })

    # Keyboard shortcuts
    # Ctrl+A: expand all
    # Ctrl+Shift+A: collapse all
    $TicketsGrid.Add_PreviewKeyDown({
        param($sender, $e)
        try {
            if ($e.Key -ne [System.Windows.Input.Key]::A) { return }

            $mods = [System.Windows.Input.Keyboard]::Modifiers
            $ctrl  = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            $shift = ($mods -band [System.Windows.Input.ModifierKeys]::Shift)   -ne 0

            if (-not $ctrl) { return }

            if ($shift) { Collapse-AllTicketDetails } else { Expand-AllTicketDetails }
            $e.Handled = $true
        } catch { }
    })

    # Refresh (poll email first, then refresh grid)
    $BtnRefreshTickets.Add_Click({
        try {
            if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                Invoke-QOEmailTicketPoll | Out-Null
            }
        } catch { }
        Update-QOTicketsGrid
    })

    # Delete (supports multi-select)
    if ($BtnDeleteTicket) {
        $BtnDeleteTicket.Add_Click({
            try {
                $selectedItems = @($script:TicketsGrid.SelectedItems)
                if (-not $selectedItems -or $selectedItems.Count -lt 1) { return }

                $idsToDelete = @(
                    foreach ($item in $selectedItems) {
                        $id = Get-RowItemIdSafe -RowItem $item
                        if ($id) { $id }
                    }
                ) | Select-Object -Unique

                if (-not $idsToDelete -or $idsToDelete.Count -lt 1) { return }

                foreach ($id in $idsToDelete) {
                    if (Get-Command Remove-QOTicket -ErrorAction SilentlyContinue) {
                        Remove-QOTicket -Id $id | Out-Null
                        [void]$script:ExpandedTicketIds.Remove($id)
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
