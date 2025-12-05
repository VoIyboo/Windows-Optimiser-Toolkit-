# MainWindow.UI.psm1
# Minimal stub for building the main application window

function New-QOTMainWindow {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Main window XAML not found at: $Path"
    }

    # Load WPF assemblies
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Read the XAML file
    $xaml = Get-Content $Path -Raw

    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        return $window
    } catch {
        throw "Failed to load MainWindow.xaml: $($_.Exception.Message)"
    }
}

function Initialize-QOTMainWindow {
    param(
        [System.Windows.Window]$Window
    )

    # For now this does nothing.
    # Later this will bind buttons, grids, status bars, etc.

    Write-Output "Main window initialised (placeholder)."
}

Export-ModuleMember -Function New-QOTMainWindow, Initialize-QOTMainWindow

