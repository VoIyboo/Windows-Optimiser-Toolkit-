# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit (Studio Voly Edition)

$ErrorActionPreference = "Stop"

function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory)]
        $SplashWindow
    )

    $basePath = Join-Path $PSScriptRoot ".."

    # ------------------------------------------------------------
    # Core imports (hard requirements)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # Discover Settings core module (path-safe)
    # ------------------------------------------------------------
    $settingsPath = Get-ChildItem -Path $basePath -Recurse -File -Filter "Settings.psm1" |
        Where-Object { $_.FullName -match "\\Core\\Settings\\Settings\.psm1$" } |
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $settingsPath) {
        throw "Settings.psm1 not found under Core\Settings"
    }

    Import-Module $settingsPath -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # Tickets core (hard requirement for Tickets tab)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Core\Tickets.psm1") -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules (soft load)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1") -Force -ErrorAction SilentlyContinue

    # Ensure no stale Tickets UI function exists
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue

    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1") -Force -ErrorAction SilentlyContinue

    # Discover Settings UI module safely
    $settingsUiPath = Get-ChildItem -Path $basePath -Recurse -File -Filter "Settings.UI.psm1" |
        Where-Object { $_.FullName -match "\\Core\\Settings\\Settings\.UI\.psm1$" } |
        Select-Object -First 1 -ExpandProperty FullName

    if ($settingsUiPath) {
        Import-Module $settingsUiPath -Force -ErrorAction SilentlyContinue
    }

    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "MainWindow.xaml not found at: $xamlPath"
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml   = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    # ------------------------------------------------------------
    # Wire Tickets UI
    # ------------------------------------------------------------
    try {
        if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
            Initialize-QOTicketsUI -Window $window
        }
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Tickets UI failed to initialise.`r`n$($_.Exception.Message)"
        ) | Out-Null
    }

    # ------------------------------------------------------------
    # Wire Settings gear button
    # ------------------------------------------------------------
    try {
        $btnSettings = $window.FindName("BtnSettings")

        if ($btnSettings) {
            $btnSettings.Add_Click({
                try {
                    if (-not (Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue)) {
                        [System.Windows.MessageBox]::Show(
                            "Settings UI not available. Check Settings.UI.psm1 exports."
                        ) | Out-Null
                        return
                    }

                    $content = New-QOTSettingsView

                    $sw = New-Object System.Windows.Window
                    $sw.Title = "Settings"
                    $sw.Width = 520
                    $sw.Height = 360
                    $sw.WindowStartupLocation = "CenterOwner"
                    $sw.Owner = $window
                    $sw.Background = [System.Windows.Media.Brushes]::Transparent
                    $sw.Content = $content

                    $null = $sw.ShowDialog()
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Failed to open Settings.`r`n$($_.Exception.Message)"
                    ) | Out-Null
                }
            })
        }
    }
    catch {
        # Never crash the app for settings
    }

    # ------------------------------------------------------------
    # Close splash
    # ------------------------------------------------------------
    try {
        if ($SplashWindow) { $SplashWindow.Close() }
    }
    catch { }

    # ------------------------------------------------------------
    # Show main window
    # ------------------------------------------------------------
    $null = $window.ShowDialog()
}

Export-ModuleMember -Function Start-QOTMainWindow
