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

