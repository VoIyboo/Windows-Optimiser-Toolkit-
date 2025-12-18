# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory)]
        $SplashWindow
    )

    $basePath = Join-Path $PSScriptRoot ".."

    # ------------------------------------------------------------
    # Core modules
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings.psm1")        -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")         -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")   -Force -ErrorAction Stop

    # ✅ ACTUAL Settings UI location (from your screenshot)
    Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1") -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path $xamlPath)) {
        throw "MainWindow.xaml not found at $xamlPath"
    }

    $xaml   = Get-Content $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
    if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
        Initialize-QOTicketsUI -Window $window
    }

    # ------------------------------------------------------------
    # Settings gear button
    # ------------------------------------------------------------
       $btnSettings = $window.FindName("BtnSettings")
    if ($btnSettings) {
        $btnSettings.Add_Click({
            try {
                $content = Initialize-QOSettingsUI -Window $window
    
                $sw = New-Object System.Windows.Window
                $sw.Title = "Settings"
                $sw.Width = 600
                $sw.Height = 420
                $sw.Owner = $window
                $sw.WindowStartupLocation = "CenterOwner"
                $sw.Content = $content
    
                $sw.ShowDialog() | Out-Null
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    "Failed to open Settings.`r`n$($_.Exception.Message)"
                ) | Out-Null
            }
        })
    }


    # ------------------------------------------------------------
    # Close splash + show main window
    # ------------------------------------------------------------
    try {
        if ($SplashWindow) { $SplashWindow.Close() }
    } catch { }

    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow
