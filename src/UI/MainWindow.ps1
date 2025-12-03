# MainWindow.ps1
# Defines Show-QMainWindow which loads the WPF MainWindow.xaml

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

function Show-QMainWindow {
    param(
        [switch]$FromBootstrap
    )

    # Locate the XAML file next to this script
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

    # Grab key controls so the engine / modules can talk to them
    $Global:QOT_StatusLabel  = $window.FindName("StatusLabel")
    $Global:QOT_MainProgress = $window.FindName("MainProgress")
    $Global:QOT_SummaryText  = $window.FindName("SummaryText")
    $Global:QOT_RunButton    = $window.FindName("RunButton")
    $Global:QOT_ModeCombo    = $window.FindName("ModeCombo")
    $Global:QOT_MainTabs     = $window.FindName("MainTabs")

    if ($Global:QOT_StatusLabel) {
        $Global:QOT_StatusLabel.Text = "Idle"
    }

    # Simple status helper, only define it if nothing else has already
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
                if ($Busy) {
                    $Global:QOT_MainProgress.Value = 0
                } else {
                    $value = [Math]::Min([Math]::Max($Progress, 0), 100)
                    $Global:QOT_MainProgress.Value = $value
                }
            }

            if ($Global:QOT_RunButton) {
                $Global:QOT_RunButton.IsEnabled = -not $Busy
            }
        }
    }

    # Wire the Run button with a temporary placeholder handler
    if ($Global:QOT_RunButton) {
        $Global:QOT_RunButton.Add_Click({
            Set-QStatus -Text "Run button wired - engine actions still to be connected." -Progress 0 -Busy:$false
        })
    }

    # Default summary text if nothing has set it yet
    if ($Global:QOT_SummaryText -and
        [string]::IsNullOrWhiteSpace($Global:QOT_SummaryText.Text)) {

        $Global:QOT_SummaryText.Text =
            "System summary will appear here once the engine scan is implemented."
    }

    # Show the window
    $null = $window.ShowDialog()
}
