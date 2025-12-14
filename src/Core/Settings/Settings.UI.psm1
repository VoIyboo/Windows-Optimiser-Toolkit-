$ErrorActionPreference = "Stop"

function Initialize-QOSettingsUI {
    param(
        [Parameter(Mandatory)]
        $Window,

        [Parameter(Mandatory)]
        [scriptblock]$OnBack
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent
    $root.Padding = "0"

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" })) | Out-Null
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))    | Out-Null

    $header = New-Object System.Windows.Controls.DockPanel
    $header.LastChildFill = $true
    $header.Margin = "0,0,0,10"

    $btnBack = New-Object System.Windows.Controls.Button
    $btnBack.Content = "Back"
    $btnBack.Width = 90
    $btnBack.Height = 32
    $btnBack.Margin = "0,0,10,0"
    $btnBack.Add_Click({ & $OnBack })
    [System.Windows.Controls.DockPanel]::SetDock($btnBack, "Left")
    $header.Children.Add($btnBack) | Out-Null

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.VerticalAlignment = "Center"
    $header.Children.Add($title) | Out-Null

    [System.Windows.Controls.Grid]::SetRow($header, 0)
    $grid.Children.Add($header) | Out-Null

    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = "Settings page is wired up. Next we add real settings."
    $body.Margin = "2,0,0,0"
    $body.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [System.Windows.Controls.Grid]::SetRow($body, 1)
    $grid.Children.Add($body) | Out-Null

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
