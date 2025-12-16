# Tickets.psm1
$ErrorActionPreference = "Stop"

# Only import Settings here
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

$script:TicketsColumnLayoutApplying = $false
$script:TicketsGrid                 = $null

function Get-QOTicketsColumnLayout {
    (Get-QOSettings).TicketsColumnLayout
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
                if ($_.Width -and $_.Width.IsAbsolute) { $widthValue = [double]$_.Width.Value }
            } catch { }

            [pscustomobject]@{
                Header       = [string]$_.Header
                DisplayIndex = [int]$_.DisplayIndex
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
            if ([string]::IsNullOrWhiteSpace($header)) { continue }

            $col = $DataGrid.Columns |
                Where-Object { [string]$_.Header -eq $header } |
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

function Get-QOTicketEmailBody {
    param([Parameter(Mandatory)] $Ticket)

    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailBody" -and $Ticket.EmailBody) { return [string]$Ticket.EmailBody }
        if ($Ticket.PSObject.Properties.Name -contains "Body" -and $Ticket.Body) { return [string]$Ticket.Body }
        if ($Ticket.PSObject.Properties.Name -contains "Description" -and $Ticket.Description) { return [string]$Ticket.Description }

        if ($Ticket.PSObject.Properties.Name -contains "Email" -and $Ticket.Email) {
            $email = $Ticket.Email
            if ($email.PSObject.Properties.Name -contains "Body" -and $email.Body) { return [string]$email.Body }
        }
    } catch { }

    return ""
}

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
            Id        = [string]$t.Id
            EmailBody = (Get-QOTicketEmailBody -Ticket $t)
        }
    }

    $script:TicketsGrid.ItemsSource = @($rows)
}

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
    $col.CellTemplate = $template

    # put it at the end so it behaves like your old Actions column
    [void]$Grid.Columns.Add($col)
}

function Ensure-QOTicketsRowDetailsTemplate {
    param([Parameter(Mandatory)] $Grid)

    $xaml = @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border Margin="12,6,12,10" Padding="10"
          BorderThickness="1" CornerRadius="6"
          BorderBrush="#374151" Background="#020617"
          HorizontalAlignment="Stretch">
    <Grid HorizontalAlignment="Stretch">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <TextBlock Text="Email body" Foreground="#9CA3AF" FontSize="12" Margin="0,0,0,6"/>

      <Border Grid.Row="1" Padding="8" Background="#0B1220" CornerRadius="6"
              HorizontalAlignment="Stretch">
        <ScrollViewer VerticalScrollBarVisibility="Auto"
                      HorizontalScrollBarVisibility="Disabled"
                      CanContentScroll="True">
          <TextBlock Text="{Binding EmailBody}"
                     Foreground="White"
                     TextWrapping="Wrap"
                     HorizontalAlignment="Stretch" />
        </ScrollViewer>
      </Border>
    </Grid>
  </Border>
</DataTemplate>
"@


    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dt = [System.Windows.Markup.XamlReader]::Load($reader)

    $Grid.RowDetailsTemplate = $dt
    $Grid.RowDetailsVisibilityMode = "Collapsed"
}

function Toggle-QOTicketDetails {
    param([Parameter(Mandatory)] $Row)

    if (-not $Row) { return }

    if ($Row.DetailsVisibility -eq [System.Windows.Visibility]::Visible) {
        $Row.DetailsVisibility = [System.Windows.Visibility]::Collapsed
    }
    else {
        $Row.DetailsVisibility = [System.Windows.Visibility]::Visible
    }
}

function Wire-QOTicketsExpanderClicks {
    param([Parameter(Mandatory)] $Grid)

    # Handle the expander button click by walking up the visual tree to the DataGridRow
    $Grid.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($sender, $e)

        try {
            $src = $e.OriginalSource
            if (-not $src) { return }

            $btn = $src -as [System.Windows.Controls.Button]
            if (-not $btn) { return }

            # only our expander buttons have Tag = DataGridRow (from template)
            $row = $btn.Tag -as [System.Windows.Controls.DataGridRow]
            if ($row) {
                Toggle-QOTicketDetails -Row $row
                $e.Handled = $true
            }
        } catch { }
    })
}

function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)] $TicketsGrid,
        [Parameter(Mandatory)] $BtnRefreshTickets,
        [Parameter(Mandatory)] $BtnNewTicket,
        [Parameter(Mandatory = $false)] $BtnDeleteTicket
    )

    $script:TicketsGrid = $TicketsGrid

    # Make the grid behave like a ticket list, not an editable spreadsheet
    $TicketsGrid.IsReadOnly            = $true
    $TicketsGrid.CanUserAddRows        = $false
    $TicketsGrid.CanUserDeleteRows     = $false
    $TicketsGrid.CanUserReorderColumns = $true
    $TicketsGrid.CanUserResizeColumns  = $true
    $TicketsGrid.SelectionUnit         = "FullRow"
    $TicketsGrid.SelectionMode         = "Extended"

    Ensure-QOTicketsExpanderColumn -Grid $TicketsGrid
    Ensure-QOTicketsRowDetailsTemplate -Grid $TicketsGrid
    Wire-QOTicketsExpanderClicks -Grid $TicketsGrid

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
                        if ($null -ne $item -and ($item.PSObject.Properties.Name -contains 'Id')) {
                            if (-not [string]::IsNullOrWhiteSpace($item.Id)) { [string]$item.Id }
                        }
                    }
                ) | Select-Object -Unique

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
