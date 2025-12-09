# Splash.UI.psm1
# Handles displaying and updating the splash/loading window

# Loads XAML from file and returns the WPF window
function New-QOTSplashWindow {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Splash XAML not found at: $Path"
    }

    # Load XAML
    $xamlContent = Get-Content $Path -Raw
    $window      = [Windows.Markup.XamlReader]::Parse($xamlContent)

    # Try to wire up the Studio Voly logo image manually
    try {
        $logoControl = $window.FindName("LogoImage")
        if ($logoControl -and $logoControl -is [System.Windows.Controls.Image]) {

            # Image lives next to Splash.xaml
            $xamlFolder = Split-Path $Path -Parent
            $logoPath   = Join-Path $xamlFolder "StudioVolySplash.png"

            if (Test-Path $logoPath) {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.UriSource   = New-Object System.Uri($logoPath, [System.UriKind]::Absolute)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()

                $logoControl.Source = $bitmap
            }
        }
    } catch {
        # If anything fails, we just skip the logo rather than crashing the splash
    }

    return $window
}

# Updates status text in the splash window
function Update-QOTSplashStatus {
    param(
        [object]$Window,
        [string]$Text
    )

    try {
        $label = $Window.FindName("SplashStatusText")
        if ($label) { $label.Text = $Text }
    } catch { }
}

# Updates progress bar value
function Update-QOTSplashProgress {
    param(
        [object]$Window,
        [int]$Value
    )

    try {
        $bar = $Window.FindName("SplashProgressBar")
        if ($bar) { $bar.Value = $Value }
    } catch { }
}

Export-ModuleMember -Function `
    New-QOTSplashWindow, `
    Update-QOTSplashStatus, `
    Update-QOTSplashProgress
