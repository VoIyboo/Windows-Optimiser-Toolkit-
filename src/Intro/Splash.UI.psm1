# Splash.UI.psm1
# Handles displaying and updating the splash/loading window

# Path to Base64-encoded fox image (one long line)
$script:FoxImagePath = Join-Path $PSScriptRoot "studio_voly_splash.txt"

# Convert Base64 into a WPF ImageSource
function Get-QOTFoxImage {
    try {
        if (-not (Test-Path $script:FoxImagePath)) { return $null }

        $base64 = Get-Content $script:FoxImagePath -Raw
        if (-not $base64) { return $null }

        $bytes = [Convert]::FromBase64String($base64)

        $ms = New-Object System.IO.MemoryStream
        $ms.Write($bytes, 0, $bytes.Length)
        $ms.Position = 0

        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit()
        $img.StreamSource = $ms
        $img.CacheOption  = "OnLoad"
        $img.EndInit()

        return $img
    }
    catch {
        return $null
    }
}

# Loads XAML from file and returns the WPF window
function New-QOTSplashWindow {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Splash XAML not found at: $Path"
    }

    $xamlContent = Get-Content $Path -Raw
    $window      = [Windows.Markup.XamlReader]::Parse($xamlContent)

    # Try to apply the fox logo
    try {
        $logoCtrl = $window.FindName("LogoImage")
        if ($logoCtrl) {
            $img = Get-QOTFoxImage
            if ($img) {
                $logoCtrl.Source = $img
            }
        }
    } catch { }

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

# Exported functions
Export-ModuleMember -Function `
    New-QOTSplashWindow, `
    Update-QOTSplashStatus, `
    Update-QOTSplashProgress
