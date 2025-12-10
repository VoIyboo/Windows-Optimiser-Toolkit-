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

    $xamlContent = Get-Content $Path -Raw
    $window = [Windows.Markup.XamlReader]::Parse($xamlContent)

    # Try to wire up the Studio Voly logo from disk
    try {
        $logoControl = $window.FindName("LogoImage")
        if ($logoControl) {
            # repo root = parent of parent of this module folder (src\Intro)
            $rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $logoPath = Join-Path $rootPath "src\Intro\StudioVolySplash.png"

            if (Test-Path $logoPath) {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.UriSource = New-Object System.Uri($logoPath, [System.UriKind]::Absolute)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()

                $logoControl.Source = $bitmap
            } else {
                Write-Host "Splash logo not found at $logoPath" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Failed to load splash logo: $($_.Exception.Message)" -ForegroundColor Yellow
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

# Clean export list
Export-ModuleMember -Function New-QOTSplashWindow, Update-QOTSplashStatus, Update-QOTSplashProgress
