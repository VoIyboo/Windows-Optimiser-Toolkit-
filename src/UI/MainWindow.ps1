# MainWindow.ps1
# Defines Show-QMainWindow which loads the WPF MainWindow.xaml

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

function Show-QMainWindow {
    param(
        [switch]$FromBootstrap
    )

    # Work out where MainWindow.xaml lives next to this script
    $thisDir  = Split-Path -Parent $PSCommandPath
    $xamlPath = Join-Path $thisDir "MainWindow.xaml"

    if (-not (Test-Path $xamlPath)) {
        [System.Windows.MessageBox]::Show(
            "MainWindow.xaml not found at:`n$xamlPath",
            "Quinn Optimiser Toolkit",
            'OK',
            'Error'
        ) | Out-Null
        return
    }

    # Load XAML and create window
    $xaml   = Get-Content -Path $xamlPath -Raw
    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    # Grab key controls so the engine / UI code can talk to them
    $Global:QOT_StatusLabel   = $window.FindName("StatusLabel")
    $Global:QOT_MainProgress  = $window.FindName("MainProgress")
    $Global:QOT_SummaryText   = $window.FindName("SummaryText")
    $Global:QOT_RunButton     = $window.FindName("RunButton")
    $Global:QOT_ModeCombo     = $window.FindName("ModeCombo")
    $Global:QOT_MainTabs      = $window.FindName("MainTabs")

    if ($Global:QOT_StatusLabel) { $Global:QOT_StatusLabel.Text = "Idle" }

    # Simple status helper, only if nothing else has defined it
    if (-not (Get-Command -Name Set-QStatus -ErrorAction SilentlyContinue)) {
        function Set-QStatus {
            param(
                [string]$Text,
                [int]$Progress = 0,
                [bool]$Busy = $false
            )

            if ($Global:QOT_StatusLabel) {
                $Global:QOT_StatusLabel.Text = $Text
            }

            if ($Global:QOT_MainProgress) {
                $Global:QOT_MainProgress.IsIndeterminate = $Busy
                if (-not $Busy) {
                    $Global:QOT_MainProgress.Value =
                        [Math]::Min([Math]::Max($Progress, 0), 100)
                } else {
                    $Global:QOT_MainProgress.Value = 0
                }
            }

            if ($Global:QOT_RunButton) {
                $Global:QOT_RunButton.IsEnabled = -not $Busy
            }
        }
    }

    # Wire Run button for now with a placeholder until Engine.psm1 hooks in
    if ($Global:QOT_RunButton) {
        $Global:QOT_RunButton.Add_Click({
            Set-QStatus "Run button wired – engine actions still to be connected." 0 $false
        })
    }

    # Default summary text if the engine hasn’t updated it yet
    if ($Global:QOT_SummaryText -and
        [string]::IsNullOrWhiteSpace($Global:QOT_SummaryText.Text)) {

        $Global:QOT_SummaryText.Text =
            "System summary will appear here once the engine scan is implemented."
    }

    # Show the window modally
    $null = $window.ShowDialog()
}

