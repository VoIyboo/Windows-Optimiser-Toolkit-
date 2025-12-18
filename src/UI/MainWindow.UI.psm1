# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit (Studio Voly Edition)

$ErrorActionPreference = "Stop"

function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        $SplashWindow
    )

    $basePath = Join-Path $PSScriptRoot ".."

    # Core imports (hard)
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force -ErrorAction Stop

    # Core imports (soft)
    Import-Module (Join-Path $basePath "Core\Settings.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")  -Force -ErrorAction SilentlyContinue

    # UI modules (soft)
    Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1")     -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "UI\Settings.UI.psm1")   -Force -ErrorAction SilentlyContinue

    # If an earlier module defined Initialize-QOTicketsUI, remove it so the correct one can load
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue

    # Load XAML for MainWindow
    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "MainWindow.xaml not found at: $xamlPath"
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load MainWindow from XAML."
    }

    # Close splash safely
    try {
        if ($SplashWindow) { $SplashWindow.Close() }
    } catch { }

    # Show main window
    $null = $window.ShowDialog()
}

Export-ModuleMember -Function Start-QOTMainWindow
