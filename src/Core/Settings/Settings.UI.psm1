# src/UI/Settings.UI.psm1
$ErrorActionPreference = "Stop"

function Initialize-QOSettingsUI {
    param(
        [Parameter(Mandatory)]
        $Window,
        [Parameter(Mandatory)]
        $OnBack
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Root container
    $root = New-Object System.Windows.Controls.Border
    $root.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $root.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    $root.BorderThickness = "1"
    $root.Padding = "12"
    $root.CornerRadius = "6"

    $grid = New-Object System.Windows.Controls.Grid

    $row1 = New-Object System.Windows.Controls.RowDefinition
    $row1.Height = "Auto"
    $row2 = New-Object System.Windows.Controls.RowDefinition
    $row2.Height = "*"
    $grid.RowDefinitions.Add($row1)
    $grid.RowDefinitions.Add($row2)

    # Header with Back button + title
    $header = New-Object System.Windows.Controls.DockPanel

    $btnBack = New-Object System.Windows.Controls.Button
    $btnBack.Content = "Back"
    $btnBack.Width = 90
    $btnBack.Height = 32
    $btnBack.Margin = "0,0,10,0"
    $btnBack.Add_Click({
        & $OnBack
    })
    [System.Windows.Controls.DockPanel]::SetDock($btnBack, "Left")
    $header.Children.Add($btnBack)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.VerticalAlignment = "Center"
    $header.Children.Add($title)

    [System.Windows.Controls.Grid]::SetRow($header, 0)
    $grid.Children.Add($header)

    # Body placeholder
    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = "Settings page loading is wired up. Next we add real settings."
    $body.Margin = "0,12,0,0"
    $body.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [System.Windows.Controls.Grid]::SetRow($body, 1)
    $grid.Children.Add($body)

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
