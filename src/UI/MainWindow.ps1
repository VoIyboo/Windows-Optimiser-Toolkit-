function Show-QMainWindow {
    Write-QLog "UI launched."

    Add-Type -AssemblyName PresentationFramework

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    $xml = Get-Content $xamlPath -Raw
    $window = [Windows.Markup.XamlReader]::Parse($xml)

    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Show-QMainWindow
