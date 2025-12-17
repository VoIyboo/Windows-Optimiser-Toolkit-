# Intro.ps1
# Responsible ONLY for splash + startup sequencing (single splash)

param(
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
$WarningPreference     = "SilentlyContinue"
$VerbosePreference     = "SilentlyContinue"
$InformationPreference = "SilentlyContinue"

# Resolve toolkit root (src\Intro\Intro.ps1 -> toolkit root)
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# WPF
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

# Load splash helpers
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1") -Force -ErrorAction Stop

# Show splash immediately
$splash = New-QOTSplashWindow -Path (Join-Path $rootPath "src\Intro\Splash.xaml")
Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 5
[void]$splash.Show()

function Set-Splash {
    param([int]$Value, [string]$Text)

    if ($Text)  { Update-QOTSplashStatus -Window $splash -Text $Text }
    if ($Value) { Update-QOTSplashProgress -Window $splash -Value $Value }

    try { $splash.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null } catch { }
}

try {
    Set-Splash -Value 15 -Text "Loading core modules..."

    # Import Engine in THIS session (so Start-QOTMain exists here)
    $enginePath = Join-Path $rootPath "src\Core\Engine\Engine.psm1"
    if (-not (Test-Path -LiteralPath $enginePath)) {
        throw "Engine module not found at: $enginePath"
    }
    Import-Module $enginePath -Force -ErrorAction Stop

    Set-Splash -Value 35 -Text "Warming up..."

    # Background warmup (optional)
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript({
        param($Root)

        $ErrorActionPreference = "Stop"

        $engine = Join-Path $Root "src\Core\Engine\Engine.psm1"
        Import-Module $engine -Force -ErrorAction Stop

        if (Get-Command Invoke-QOTStartupWarmup -ErrorAction SilentlyContinue) {
            Invoke-QOTStartupWarmup -RootPath $Root
        }

        return $true
    }).AddArgument($rootPath)

    $async = $ps.BeginInvoke()

    $p = 40
    while (-not $async.IsCompleted) {
        $p = [Math]::Min(90, $p + 2)
        Set-Splash -Value $p -Text "Loading modules..."
        Start-Sleep -Milliseconds 120
    }

    $null = $ps.EndInvoke($async)
    $ps.Dispose()

    Set-Splash -Value 100 -Text "Opening app..."
    Start-Sleep -Milliseconds 200

    # Close splash then open main window
    $splash.Close()

    Start-QOTMain -RootPath $rootPath
}
catch {
    try { $splash.Close() } catch { }

    [System.Windows.MessageBox]::Show(
        "Startup failed:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        "OK",
        "Error"
    ) | Out-Null
}
