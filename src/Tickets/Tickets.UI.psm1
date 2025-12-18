$path = "C:\Users\amillar\AppData\Local\Temp\QuinnOptimiserToolkit\Windows-Optimiser-Toolkit--main\src\Tickets\Tickets.UI.psm1"

@'
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

$script:ExpandedTicketIds = New-Object 'System.Collections.Generic.HashSet[string]'

$script:RowDetailsHeightDefault = 240
$script:RowDetailsHeight        = $script:RowDetailsHeightDefault
$script:RowDetailsHeightMin     = 120
$script:RowDetailsHeightMax     = 900

# -------------------------------------------------------------------
# Email polling timer (auto refresh)
# -------------------------------------------------------------------
$script:TicketsPollTimer = $null

function Start-QOTicketsAutoPoll {
    param(
        [int] $IntervalSeconds = 60
    )

    try {
        if ($script:TicketsPollTimer) {
            try { $script:TicketsPollTimer.Stop() } catch { }
            $script:TicketsPollTimer = $null
        }

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds($IntervalSeconds)

        $timer.add_Tick({
            try {
                if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                    Invoke-QOEmailTicketPoll | Out-Null
                }
            } catch { }

            try { Update-QOTicketsGrid } catch { }
        })

        $timer.Start()
        $script:TicketsPollTimer = $timer
    } catch {
        Write-Warning ("Tickets UI: failed to start auto poll. {0}" -f $_.Exception.Message)
    }
}

function Stop-QOTicketsAutoPoll {
    try {
        if ($script:TicketsPollTimer) {
            try { $script:TicketsPollTimer.Stop() } catch { }
            $script:TicketsPollTimer = $null
        }
    } catch { }
}




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
                $actualWidth = $_.ActualWidth
                if ($actualWidth -gt 0) { $widthValue = [double]$actualWidth }
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

function Set-QORowDetailsHeight {
    param([Parameter(Mandatory)] [double] $NewHeight)

    $h = [Math]::Round($NewHeight)

    if ($h -lt $script:RowDetailsHeightMin) { $h = $script:RowDetailsHeightMin }
    if ($h -gt $script:RowDetailsHeightMax) { $h = $script:RowDetailsHeightMax }

    $script:RowDetailsHeight = $h

    try {
        if ($script:TicketsGrid) { $script:TicketsGrid.Tag = $script:RowDetailsHeight }
    } catch { }
}

function Save-QORowDetailsHeightSetting {
    try {
        $s = Get-QOSettings
        $s | Add-Member -NotePropertyName TicketsRowDetailsHeight -NotePropertyValue ([double]$script:RowDetailsHeight) -Force
        Save-QOSettings -Settings $s
    } catch { }
}

function Set-TicketStatusReadIfNew {
    param([Parameter(Mandatory)] [string] $Id)

    try {
        if (-not (Get-Command Get-QOTickets -ErrorAction SilentlyContinue)) { return }
        if (-not (Get-Command Save-QOTickets -ErrorAction SilentlyContinue)) { return }

        $db = Get-QOTickets
        if (-not $db -or -not $db.Tickets) { return }

        $t = @($db.Tickets) | Where-Object { [string]$_.Id -eq $Id } | Select-Object -First 1
        if (-not $t) { return }

        if ([string]$t.Status -eq 'New') {
            $t.Status = 'Read'
            Save-QOTickets -Db $db | Out-Null
        }
    } catch { }
}

function Toggle-TicketRowDetails {
    param([Parameter(Mandatory)] $RowItem)

    $id = Get-RowItemIdSafe -RowItem $RowItem
    if (-not $id) { return }

    $expanded = $false
    if ($script:ExpandedTicketIds.Contains($id)) {
        [void]$script:ExpandedTicketIds.Remove($id)
        $expanded = $false
    } else {
        [void]$script:ExpandedTicketIds.Add($id)
        $expanded = $true
    }

    try {
        $row = $script:TicketsGrid.ItemContainerGenerator.ContainerFromItem($RowItem)
        if ($row -is [System.Windows.Controls.DataGridRow]) {
            Set-RowDetailsState -Row $row -Expanded $expanded
        }
    } catch { }

    if ($expanded) {
        Set-TicketStatusReadIfNew -Id $id
        Update-QOTicketsGrid
    }
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

# -------------------------------------------------------------------
# Expander column
# -------------------------------------------------------------------
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

    $template = $null
    try { $template = [System.Windows.Markup.XamlReader]::Parse($xaml) } catch { }

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
        Write-Warning ("Tickets UI: failed to load tickets. {0}" -f $_.Exception.Message)
        $tickets = @()
    }

    $rows = foreach ($t in $tickets) {
        $rawCreated = $t.CreatedAt
        $created    = $null

        if ($rawCreated -is [datetime]) { $created = $rawCreated }
        elseif ($rawCreated) { [datetime]::TryParse([string]$rawCreated, [ref]$created) | Out-Null }

        $createdString = if ($created) { $created.ToString('dd/MM/yyyy h:mm tt') } else { [string]$rawCreated }

        [pscustomobject]@{
            Title      = [string]$t.Title
            CreatedAt  = $createdString
            Status     = [string]$t.Status
            Priority   = [string]$t.Priority
            Id         = [string]$t.Id
            EmailBody  = (Get-QOTicketBodyText -Ticket $t)
            AssignedTo = [string]$t.AssignedTo
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

    try {
        $s = Get-QOSettings
        if ($s.PSObject.Properties.Name -contains 'TicketsRowDetailsHeight') {
            $val = [double]$s.TicketsRowDetailsHeight
            if ($val -gt 80) { $script:RowDetailsHeight = $val }
        }
    } catch { }

    $TicketsGrid.Add_SizeChanged({
        try {
            $cap = [Math]::Floor($script:TicketsGrid.ActualHeight * 0.60)
            if ($cap -lt 200) { $cap = 200 }
            $script:RowDetailsHeightMax = $cap

            if ($script:RowDetailsHeight -gt $script:RowDetailsHeightMax) {
                Set-QORowDetailsHeight -NewHeight $script:RowDetailsHeightMax
                Save-QORowDetailsHeightSetting
            }
        } catch { }
    })

    Set-QORowDetailsHeight -NewHeight $script:RowDetailsHeight

    $TicketsGrid.IsReadOnly            = $true
    $TicketsGrid.CanUserAddRows        = $false
    $TicketsGrid.CanUserDeleteRows     = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true
    $TicketsGrid.SelectionUnit         = "FullRow"
    $TicketsGrid.SelectionMode         = "Extended"

    try { $TicketsGrid.EnableRowVirtualization    = $false } catch { }
    try { $TicketsGrid.EnableColumnVirtualization = $true  } catch { }

    try {
        $TicketsGrid.SetValue(
            [System.Windows.Controls.ScrollViewer]::CanContentScrollProperty,
            $false
        )
    } catch { }

    try { $TicketsGrid.HorizontalScrollBarVisibility = 'Disabled' } catch { }
    try { $TicketsGrid.RowDetailsVisibilityMode      = 'Collapsed' } catch { }

    Ensure-QOTicketsExpanderColumn -Grid $TicketsGrid
    Wire-QOTicketsExpanderClicks   -Grid $TicketsGrid

    $rowDetailsXaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border Margin="10,4,10,10"
          CornerRadius="6"
          BorderThickness="1"
          BorderBrush="#374151"
          Background="#020617"
          Padding="10"
          HorizontalAlignment="Stretch">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <ScrollViewer Grid.Row="0"
                    VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled"
                    PanningMode="VerticalFirst"
                    CanContentScroll="False"
                    Height="{Binding RelativeSource={RelativeSource AncestorType=DataGrid}, Path=Tag}"
                    HorizontalAlignment="Stretch">
        <TextBlock Text="{Binding EmailBody}"
                   Foreground="White"
                   TextWrapping="Wrap"
                   FontSize="13"
                   LineHeight="18"
                   HorizontalAlignment="Stretch"/>
      </ScrollViewer>

      <Thumb Grid.Row="1"
             Tag="RowDetailsResizer"
             Height="10"
             Margin="0,8,0,0"
             Cursor="SizeNS"
             Opacity="0.6">
        <Thumb.Template>
          <ControlTemplate TargetType="Thumb">
            <Border Height="10"
                    CornerRadius="4"
                    Background="#374151"/>
          </ControlTemplate>
        </Thumb.Template>
      </Thumb>
    </Grid>
  </Border>
</DataTemplate>
"@

    try {
        $TicketsGrid.RowDetailsTemplate = [System.Windows.Markup.XamlReader]::Parse($rowDetailsXaml)
    } catch {
        Write-Warning ("Tickets UI: failed to apply RowDetailsTemplate. {0}" -f $_.Exception.Message)
    }

    $TicketsGrid.Add_Loaded({
        Update-QOTicketsGrid
        Apply-QOTicketsColumnLayout -DataGrid $script:TicketsGrid
    })

    $TicketsGrid.Add_ColumnReordered({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) { Save-QOTicketsColumnLayout -DataGrid $sender }
    })

    $TicketsGrid.Add_ColumnDisplayIndexChanged({
        param($sender, $eventArgs)
        if (-not $script:TicketsColumnLayoutApplying) { Save-QOTicketsColumnLayout -DataGrid $sender }
    })

    $TicketsGrid.Add_PreviewMouseLeftButtonUp({
        try {
            if (-not $script:TicketsColumnLayoutApplying) {
                Save-QOTicketsColumnLayout -DataGrid $script:TicketsGrid
            }
        } catch { }
    })

    $TicketsGrid.AddHandler(
        [System.Windows.Controls.Primitives.Thumb]::DragDeltaEvent,
        [System.Windows.Controls.Primitives.DragDeltaEventHandler]{
            param($sender, $e)
            try {
                $thumb = $e.OriginalSource -as [System.Windows.Controls.Primitives.Thumb]
                if (-not $thumb) { return }
                if ($thumb.Tag -ne 'RowDetailsResizer') { return }

                $new = [double]$script:RowDetailsHeight + [double]$e.VerticalChange
                Set-QORowDetailsHeight -NewHeight $new
                Save-QORowDetailsHeightSetting
            } catch { }
        },
        $true
    )

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

    $TicketsGrid.Add_MouseDoubleClick({
        try {
            $item = $script:TicketsGrid.SelectedItem
            if ($item) { Toggle-TicketRowDetails -RowItem $item }
        } catch { }
    })

    $TicketsGrid.Add_PreviewKeyDown({
        param($sender, $e)
        try {
            if ($e.Key -ne [System.Windows.Input.Key]::A) { return }

            $mods  = [System.Windows.Input.Keyboard]::Modifiers
            $ctrl  = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            $shift = ($mods -band [System.Windows.Input.ModifierKeys]::Shift)   -ne 0
            if (-not $ctrl) { return }

            if ($shift) { Collapse-AllTicketDetails } else { Expand-AllTicketDetails }
            $e.Handled = $true
        } catch { }
    })

    $BtnRefreshTickets.Add_Click({
        try {
            if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                Invoke-QOEmailTicketPoll | Out-Null
            }
        } catch { }
        Update-QOTicketsGrid
    })

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
            } catch {
                Write-Warning ("Tickets UI: failed to delete ticket(s). {0}" -f $_.Exception.Message)
            }
            Update-QOTicketsGrid
        })
    }

    $BtnNewTicket.Add_Click({
        try {
            $now = Get-Date

            if (Get-Command New-QOTicket -ErrorAction SilentlyContinue) {
                $ticket = New-QOTicket `
                    -Title ("Test ticket {0}" -f $now.ToString("HH:mm")) `
                    -Description "Test ticket created from the UI." `
                    -Category "Testing" `
                    -Priority "Low"
            } else {
                $ticket = [pscustomobject]@{
                    Id          = [guid]::NewGuid().ToString()
                    Title       = ("Test ticket {0}" -f $now.ToString("HH:mm"))
                    Description = "Test ticket created from the UI."
                    Category    = "Testing"
                    Priority    = "Low"
                    Status      = "New"
                    CreatedAt   = $now.ToString("o")
                    AssignedTo  = ""
                }
            }

            if (Get-Command Add-QOTicket -ErrorAction SilentlyContinue) {
                Add-QOTicket -Ticket $ticket | Out-Null
            } else {
                throw "Add-QOTicket not found. Tickets.psm1 core is missing Add-QOTicket."
            }
        } catch {
            Write-Warning ("Tickets UI: failed to create ticket. {0}" -f $_.Exception.Message)
        }

        Update-QOTicketsGrid
    })

    Update-QOTicketsGrid
}

Export-ModuleMember -Function Initialize-QOTicketsUI, Update-QOTicketsGrid, Apply-QOTicketsColumnOrder
'@ | Set-Content -Path $path -Encoding UTF8
"Rewrote: $path"
