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
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force
    Import-Module (Join-Path $basePath "Core\Settings.psm1")        -Force
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")         -Force

    # ------------------------------------------------------------
    # UI modules
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")   -Force
    Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1") -Force

    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    $xaml     = Get-Content $xamlPath -Raw
    $reader   = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window   = [System.Windows.Markup.XamlReader]::Load($reader)

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
    Initialize-QOTicketsUI -Window $window

    # ------------------------------------------------------------
    # Settings gear button
    # ------------------------------------------------------------
    $btnSettings = $window.FindName("BtnSettings")
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

    # ------------------------------------------------------------
    # Close splash + show main window
    # ------------------------------------------------------------
    try { $SplashWindow.Close() } catch {}
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow
