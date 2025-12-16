# Splash.UI.psm1
# Handles displaying and updating the splash/loading window

# Load XAML from file and return the WPF window, with logo wired up
function New-QOTSplashWindow {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Splash XAML not found at: $Path"
    }

    $xamlContent = Get-Content $Path -Raw
    $window      = [Windows.Markup.XamlReader]::Parse($xamlContent)

    # After the window is created, attach the Studio Voly logo
    try {
        $imageControl = $window.FindName("FoxLogoImage")
        if ($imageControl) {
            $pngPath = Join-Path $PSScriptRoot "StudioVolySplash.png"

            if (Test-Path $pngPath) {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.UriSource   = New-Object System.Uri($pngPath, [System.UriKind]::Absolute)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()

                $imageControl.Source = $bitmap
            }
        }
    }
    catch {
        # If anything goes wrong, just continue without the image
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
        if (-not $label) { return }

        if ($label -is [System.Windows.Controls.TextBlock] -or
            $label -is [System.Windows.Controls.TextBox]) {
            $label.Text = $Text
        }
        else {
            $label.Content = $Text
        }
    }
    catch { }
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
    }
    catch { }
}

Export-ModuleMember -Function `
    New-QOTSplashWindow, `
    Update-QOTSplashStatus, `
    Update-QOTSplashProgress
