# Splash.UI.psm1
# Handles displaying and updating the splash/loading window

function New-QOTSplashWindow {
    param(
        [string]$Path,
        [string]$LogoPath
    )

    if (-not (Test-Path $Path)) {
        throw "Splash XAML not found at: $Path"
    }

    $xamlContent = Get-Content $Path -Raw
    $window      = [Windows.Markup.XamlReader]::Parse($xamlContent)

    # Attach Studio Voly logo if available
    try {
        if ($LogoPath -and (Test-Path $LogoPath)) {
            $img = $window.FindName("FoxLogoImage")
            if ($img) {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.UriSource   = [Uri]::new($LogoPath)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()
                $img.Source = $bitmap
            }
        }
    } catch {
        # If image fails, just continue with glow + progress
    }

    return $window
}

function Update-QOTSplashStatus {
    param(
        [object]$Window,
        [string]$Text
    )

    try {
        $label = $Window.FindName("SplashStatusText")
        if ($label) {
            $label.Dispatcher.Invoke({
                param($t)
                $this.Text = $t
            }, $Text)
        }
    } catch { }
}

function Update-QOTSplashProgress {
    param(
        [object]$Window,
        [int]$Value
    )

    try {
        $bar = $Window.FindName("SplashProgressBar")
        if ($bar) {
            $bar.Dispatcher.Invoke({
                param($v)
                $this.Value = $v
            }, $Value)
        }
    } catch { }
}

Export-ModuleMember -Function `
    New-QOTSplashWindow, `
    Update-QOTSplashStatus, `
    Update-QOTSplashProgress
