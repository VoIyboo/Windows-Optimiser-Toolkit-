# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit (Studio Voly Edition)

$ErrorActionPreference = "Stop"

function Find-QOTFile {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FileName,
        [string[]]$PreferRegex = @()
    )

    $all = @(Get-ChildItem -Path $Root -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { return $null }

    foreach ($rx in $PreferRegex) {
        $hit = $all | Where-Object { $_.FullName -match $rx } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    return ($all | Select-Object -First 1).FullName
}

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
    # Find + import Settings core (path-flexible)
    # ------------------------------------------------------------
    $settingsPath = Find-QOTFile -Root (Join-Path $basePath "Core") -FileName "Settings.psm1" -PreferRegex @(
        "\\Core\\Settings\\Settings\.psm1$",
        "\\Core\\Settings\.psm1$"
    )

    if (-not $settingsPath) {
        throw "Could not locate Settings.psm1 anywhere under: $(Join-Path $basePath 'Core')"
    }

    Import-Module $settingsPath -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # Tickets core (required for Tickets tab)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Core\Tickets.psm1") -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules (soft load)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1") -Force -ErrorAction SilentlyContinue

    # Ensure no stale Tickets UI function exists
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1") -Force -ErrorAction SilentlyContinue

    # Settings UI (optional)
    $settingsUiPath = Find-QOTFile -Root $basePath -FileName "Settings.UI.psm1" -PreferRegex @(
        "\\Core\\Settings\\Settings\.UI\.psm1$",
        "\\UI\\Settings\.UI\.psm1$",
        "\\Settings\.UI\.psm1$"
    )

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
        [System.Windows.MessageBox]::Show("Tickets UI failed to initialise.`r`n$($_.Exception.Message)") | Out-Null
    }

    # ------------------------------------------------------------
    # Wire Settings gear button
    # ------------------------------------------------------------
    try {
        $btnSettings = $window.FindName("BtnSettings")

        if ($btnSettings) {
            $btnSettings.Add_Click({
                try {
                    if (Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue) {
                        $content = New-QOTSettingsView
                    }
                    elseif (Get-Command Initialize-QOSettingsUI -ErrorAction SilentlyContinue) {
                        $content = Initialize-QOSettingsUI -Window $null
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Settings UI function not found. Check Settings.UI.psm1 exports.") | Out-Null
                        return
                    }

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
                    [System.Windows.MessageBox]::Show("Failed to open Settings.`r`n$($_.Exception.Message)") | Out-Null
                }
            })
        }
    } catch { }

    # ------------------------------------------------------------
    # Close splash
    # ------------------------------------------------------------
    try {
        if ($SplashWindow) { $SplashWindow.Close() }
    } catch { }

    # ------------------------------------------------------------
    # Show main window
    # ------------------------------------------------------------
    $null = $window.ShowDialog()
}

Export-ModuleMember -Function Start-QOTMainWindow
