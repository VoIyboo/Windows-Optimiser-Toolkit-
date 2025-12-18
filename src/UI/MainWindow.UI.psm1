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
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")     -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1")   -Force -ErrorAction Stop

    # Core imports (use your actual folder structure)
    Import-Module (Join-Path $basePath "Core\Settings\Settings.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")           -Force -ErrorAction Stop

    # UI modules (soft so one broken tab doesn't kill the app)
    Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1")               -Force -ErrorAction SilentlyContinue

    # IMPORTANT: remove stale function BEFORE importing Tickets UI
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")         -Force -ErrorAction SilentlyContinue

    Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1")  -Force -ErrorAction SilentlyContinue

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

    # Wire Tickets UI
    try {
        if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
            Initialize-QOTicketsUI -Window $window
        }
    } catch { }

    # Wire Settings button
    try {
        $btnSettings = $window.FindName("BtnSettings")
        if ($btnSettings) {
            $btnSettings.Add_Click({
                try {
                    if (Get-Command Show-QOSettingsWindow -ErrorAction SilentlyContinue) {
                        Show-QOSettingsWindow -Owner $window
                    }
                    elseif (Get-Command Initialize-QOSettingsUI -ErrorAction SilentlyContinue) {
                        Initialize-QOSettingsUI -Window $window
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Settings UI function not found. Check Core\Settings\Settings.UI.psm1 exports.") | Out-Null
                    }
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to open Settings.`r`n$($_.Exception.Message)") | Out-Null
                }
            })
        }
    } catch { }

    # Close splash safely
    try {
        if ($SplashWindow) { $SplashWindow.Close() }
    } catch { }

    # Show main window
    $null = $window.ShowDialog()
}

Export-ModuleMember -Function Start-QOTMainWindow
