function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory = $false)]
        [System.Windows.Window]$SplashWindow
    )

    try {
        $window = Initialize-QOTMainWindow
        if (-not $window) { throw "Initialize-QOTMainWindow returned null. Main window was not created." }

        # Ensure we have a real WPF Application object (fixes lots of ShowDialog weirdness)
        $app = [System.Windows.Application]::Current
        if (-not $app) {
            $app = New-Object System.Windows.Application
            $app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
        }

        # Close splash AFTER main is rendered, with Ready + 2s + fade.
        if ($SplashWindow) {
            $window.Add_ContentRendered({
                try {
                    $bar = $SplashWindow.FindName("SplashProgressBar")
                    $txt = $SplashWindow.FindName("SplashStatusText")

                    if ($bar) { $bar.Value = 100 }
                    if ($txt) { $txt.Text  = "Ready" }

                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromSeconds(2)
                    $timer.Add_Tick({
                        $timer.Stop()

                        try {
                            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                            $anim.From = 1
                            $anim.To = 0
                            $anim.Duration = [TimeSpan]::FromMilliseconds(300)
                            $SplashWindow.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
                        } catch { }

                        $t2 = New-Object System.Windows.Threading.DispatcherTimer
                        $t2.Interval = [TimeSpan]::FromMilliseconds(330)
                        $t2.Add_Tick({
                            $t2.Stop()
                            try { $SplashWindow.Close() } catch { }
                        })
                        $t2.Start()
                    })
                    $timer.Start()
                } catch { }
            })
        }

        $Global:QOTMainWindow = $window
        $app.MainWindow = $window

        # Run the message loop properly instead of ShowDialog()
        [void]$window.Show()
        [void]$app.Run()
    }
    catch {
        $msg = $_.Exception.Message
        try {
            if ($_.Exception.InnerException) {
                $msg += "`nInner: " + $_.Exception.InnerException.Message
            }
        } catch { }

        Write-Error "Start-QOTMainWindow : Failed to start Quinn Optimiser Toolkit UI.`n$msg"
        throw
    }
}
