# MainWindow.ps1
# Defines Show-QMainWindow which loads MainWindow.xaml
# and wires up basic status + dashboard system health scan.

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

    # ------------------------------------------------------------------
    # Grab key global controls (status bar, run button, etc.)
    # ------------------------------------------------------------------
    $Global:QOT_StatusLabel  = $window.FindName("StatusLabel")
    $Global:QOT_MainProgress = $window.FindName("MainProgress")
    $Global:QOT_SummaryText  = $window.FindName("SummaryText")
    $Global:QOT_RunButton    = $window.FindName("RunButton")
    $Global:QOT_ModeCombo    = $window.FindName("ModeCombo")
    $Global:QOT_MainTabs     = $window.FindName("MainTabs")

    if ($Global:QOT_StatusLabel) {
        $Global:QOT_StatusLabel.Text = "Idle"
    }

    # ------------------------------------------------------------------
    # Dashboard controls (must match x:Name values in MainWindow.xaml)
    # ------------------------------------------------------------------
    $Global:QOT_DashCpuRamText          = $window.FindName("DashCpuRamText")
    $Global:QOT_DashDiskText            = $window.FindName("DashDiskText")
    $Global:QOT_DashHealthText          = $window.FindName("DashHealthText")
    $Global:QOT_DashFoldersList         = $window.FindName("DashFoldersList")
    $Global:QOT_DashAppsList            = $window.FindName("DashAppsList")
    $Global:QOT_DashLastMaintenanceText = $window.FindName("DashLastMaintenanceText")
    $Global:QOT_DashQuickActionsText    = $window.FindName("DashQuickActionsText")
    $Global:QOT_DashScanButton          = $window.FindName("DashScanButton")

    # ------------------------------------------------------------------
    # Status helper (only define if not already present)
    # ------------------------------------------------------------------
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

    # ------------------------------------------------------------------
    # Dashboard UI updater – takes the summary object from Dashboard.psm1
    # ------------------------------------------------------------------
    function Update-QDashboardUi {
        param(
            $Summary
        )

        if (-not $Summary) { return }

        # CPU / RAM
        if ($Global:QOT_DashCpuRamText -and $Summary.CpuRam) {
            $Global:QOT_DashCpuRamText.Text = "CPU: {0}%   RAM: {1}%" -f `
                [int]$Summary.CpuRam.CpuPercent,
                [int]$Summary.CpuRam.RamPercent
        }

        # Disk
        if ($Global:QOT_DashDiskText -and $Summary.Disk) {
            $d = $Summary.Disk
            $Global:QOT_DashDiskText.Text = "{0} used / {1} free ({2} total, {3}% free)" -f `
                ("{0} GB" -f $d.UsedGB),
                ("{0} GB" -f $d.FreeGB),
                ("{0} GB" -f $d.TotalGB),
                $d.FreePercent
        }

        # Health text
        if ($Global:QOT_DashHealthText) {
            $Global:QOT_DashHealthText.Text = $Summary.HealthSummary
        }

        # Largest folders
        if ($Global:QOT_DashFoldersList) {
            $Global:QOT_DashFoldersList.Items.Clear()
            foreach ($f in $Summary.LargestFolders) {
                $Global:QOT_DashFoldersList.Items.Add(
                    ("{0}  ({1} GB)" -f $f.Path, $f.SizeGB)
                ) | Out-Null
            }
        }

        # Largest apps
        if ($Global:QOT_DashAppsList) {
            $Global:QOT_DashAppsList.Items.Clear()
            foreach ($a in $Summary.LargestApps) {
                $Global:QOT_DashAppsList.Items.Add(
                    ("{0}  ({1} MB)" -f $a.Name, $a.SizeMB)
                ) | Out-Null
            }
        }

        # Last maintenance / scan time
        if ($Global:QOT_DashLastMaintenanceText) {
            $Global:QOT_DashLastMaintenanceText.Text =
                "Last health scan: {0}" -f $Summary.ScanTime.ToString("yyyy-MM-dd HH:mm")
        }

        # Recommended quick actions
        if ($Global:QOT_DashQuickActionsText -and $Summary.RecommendedActions) {
            $Global:QOT_DashQuickActionsText.Text =
                ($Summary.RecommendedActions -join "`r`n")
        }
    }

    # ------------------------------------------------------------------
    # Wire Run button (still placeholder for now)
    # ------------------------------------------------------------------
    if ($Global:QOT_RunButton) {
        $Global:QOT_RunButton.Add_Click({
            Set-QStatus -Text "Run button wired - engine actions still to be connected." `
                         -Progress 0 `
                         -Busy:$false
        })
    }

    # Default summary text if nothing has set it yet
    if ($Global:QOT_SummaryText -and
        [string]::IsNullOrWhiteSpace($Global:QOT_SummaryText.Text)) {

        $Global:QOT_SummaryText.Text =
            "System summary will appear here once the engine scan is implemented."
    }

    # ------------------------------------------------------------------
    # Wire up the dashboard "Analyse system" button
    # ------------------------------------------------------------------
    if ($Global:QOT_DashScanButton) {
        $Global:QOT_DashScanButton.Add_Click({
            Set-QStatus "Scanning system health..." 0 $true
            try {
                if (Get-Command -Name Get-QDashboardSummary -ErrorAction SilentlyContinue) {
                    $summary = Get-QDashboardSummary
                    Update-QDashboardUi -Summary $summary
                    Set-QStatus "Idle" 0 $false
                } else {
                    if ($Global:QOT_DashHealthText) {
                        $Global:QOT_DashHealthText.Text = "Dashboard module not loaded."
                    }
                    Set-QStatus "Dashboard module not loaded." 0 $false
                }
            }
            catch {
                Write-QLog "Dashboard scan error: $($_.Exception.Message)" "ERROR"
                if ($Global:QOT_DashHealthText) {
                    $Global:QOT_DashHealthText.Text = "Scan failed. See log for details."
                }
                Set-QStatus "Error during dashboard scan." 0 $false
            }
        })
    }

        # Optional: auto scan when the window opens
    $window.Add_Loaded({
        try {
            Set-QStatus "Scanning system health..." 0 $true

            if (Get-Command -Name Get-QDashboardSummary -ErrorAction SilentlyContinue) {
                $summary = Get-QDashboardSummary
                Update-QDashboardUI -Summary $summary
            }
        } catch {
            Write-QLog ("Initial dashboard scan error: {0}" -f $_.Exception.Message) "ERROR"
        } finally {
            Set-QStatus "Idle" 0 $false
        }
    })

    # Hook dashboard controls if module is loaded
    if (Get-Command -Name Hook-QDashboardUI -ErrorAction SilentlyContinue) {
        Hook-QDashboardUI -Window $window
    }

    # Wire the "Analyse system and refresh recommendations" button
    if ($Global:QOT_RecommendButton -and (Get-Command -Name Start-QDashboardScan -ErrorAction SilentlyContinue)) {
        $Global:QOT_RecommendButton.Add_Click({
            Start-QDashboardScan
        })
    }

    # Show the window
    $null = $window.ShowDialog()
}
