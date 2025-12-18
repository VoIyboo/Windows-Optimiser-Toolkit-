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

    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "MainWindow.xaml not found at $xamlPath"
    }

    $xaml   = Get-Content -LiteralPath $xamlPath -Raw
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
    # Settings gear button (robust loader)
    # ------------------------------------------------------------
                $btnSettings = $window.FindName("BtnSettings")
                $tabs        = $window.FindName("MainTabControl")
                $tabSettings = $window.FindName("TabSettings")
                
                if ($btnSettings -and $tabs -and $tabSettings) {
                    $btnSettings.Add_Click({
                        $tabs.SelectedItem = $tabSettings
                    })
                }


                Import-Module $settingsUiPath -Force -ErrorAction Stop

                $entry = $null

                $entry = Get-Command Initialize-QOSettingsUI -ErrorAction SilentlyContinue
                if (-not $entry) { $entry = Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue }
                if (-not $entry) { $entry = Get-Command Show-QOTSettingsWindow -ErrorAction SilentlyContinue }

                if (-not $entry) {
                    $m = Get-Module | Where-Object { $_.Path -eq $settingsUiPath } | Select-Object -First 1
                    $exports = ""
                    if ($m) { $exports = ($m.ExportedCommands.Keys | Sort-Object) -join ", " }

                    if ([string]::IsNullOrWhiteSpace($exports)) { $exports = "(none found)" }

                    [System.Windows.MessageBox]::Show(
                        "Settings UI loaded, but no known entry function was exported.`r`n`r`nExported commands:`r`n$exports"
                    ) | Out-Null
                    return
                }

                # Call the entry point in a compatible way
                if ($entry.Name -eq "Show-QOTSettingsWindow") {
                    & $entry -Owner $window | Out-Null
                    return
                }

                $content = & $entry -Window $window

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
    try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow
