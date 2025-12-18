# Intro.ps1
# Fox splash startup for the Quinn Optimiser Toolkit (progress + ready + fade + swap to Main UI)

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$script:QOTLogPath = $LogPath

function Assert-ScriptBlock {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not $Value) { throw "$Name is null" }
    if (-not ($Value -is [scriptblock])) { throw "$Name is not a ScriptBlock. Actual type: $($Value.GetType().FullName)" }
}

function Get-MainWindowFromResult {
    param([Parameter(Mandatory)]$Result)

    if (-not $Result) { return $null }

    if ($Result -is [System.Windows.Window]) { return $Result }

    try {
        if ($Result -is [hashtable]) {
            if ($Result.ContainsKey("MainWindow") -and $Result["MainWindow"] -is [System.Windows.Window]) { return $Result["MainWindow"] }
            if ($Result.ContainsKey("Window")     -and $Result["Window"]     -is [System.Windows.Window]) { return $Result["Window"] }
        }

        $p = $Result.PSObject.Properties
        if ($p["MainWindow"] -and $Result.MainWindow -is [System.Windows.Window]) { return $Result.MainWindow }
        if ($p["Window"]     -and $Result.Window     -is [System.Windows.Window]) { return $Result.Window }
        if ($p["UI"]         -and $Result.UI         -is [System.Windows.Window]) { return $Result.UI }
    } catch { }

    return $null
}

$oldWarningPreference = $WarningPreference
$WarningPreference = "SilentlyContinue"

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Make logging callable inside timers / event handlers
    [scriptblock]$script:WriteLog = {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
        if (-not $Quiet) { Write-Host $line }
    }.GetNewClosure()

    $rootPath      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    $splashUIModule = Join-Path $rootPath "src\Intro\Splash.UI.psm1"
    if (Test-Path $splashUIModule) {
        Import-Module $splashUIModule -Force -ErrorAction SilentlyContinue
    }

    $splash = $null
    if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
        $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
        $splash = New-QOTSplashWindow -Path $splashXaml

        if ($splash) {
            $splash.WindowStartupLocation = "CenterScreen"
            $splash.Topmost = $true
            $splash.Show()
        }
    }

    # ==========================================================
    # Scriptblocks kept as variables and invoked via .Invoke()
    # ==========================================================

    [scriptblock]$script:SetFoxSplash = {
        param([int]$Percent, [string]$Text)

        if (-not $splash) { return }

        $splash.Dispatcher.Invoke([action]{
            $bar = $splash.FindName("SplashProgressBar")
            $txt = $splash.FindName("SplashStatusText")
            if ($bar) { $bar.Value = [double]$Percent }
            if ($txt) { $txt.Text = $Text }
        })
    }.GetNewClosure()

    [scriptblock]$script:FadeOutAndClose = {
        if (-not $splash) { return }

        $splash.Dispatcher.Invoke([action]{
            $splash.Topmost = $false

            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $anim.From = 1
            $anim.To = 0
            $anim.Duration = [TimeSpan]::FromMilliseconds(300)

            $splash.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
        })

        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(330)

        $tLocal = $t
        $t.Add_Tick( ({
            try { $tLocal.Stop() } catch { }
            try { $splash.Close() } catch { }
        }).GetNewClosure() )

        $t.Start()
    }.GetNewClosure()

    [scriptblock]$script:CompleteIntro = {
        param([string]$Reason = "normal")

        try {
            $script:SetFoxSplash.Invoke(100, "Ready")

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds(2)

            $timerLocal = $timer
            $timer.Add_Tick( ({
                try { $timerLocal.Stop() } catch { }
                try { $script:FadeOutAndClose.Invoke() } catch { }
                $script:WriteLog.Invoke("Intro completed ($Reason)", "INFO")
            }).GetNewClosure() )

            $timer.Start()
        } catch { }
    }.GetNewClosure()

    Assert-ScriptBlock $script:WriteLog        '$script:WriteLog'
    Assert-ScriptBlock $script:SetFoxSplash    '$script:SetFoxSplash'
    Assert-ScriptBlock $script:FadeOutAndClose '$script:FadeOutAndClose'
    Assert-ScriptBlock $script:CompleteIntro   '$script:CompleteIntro'

    # ==========================================================
    # Startup sequence
    # ==========================================================

    $script:SetFoxSplash.Invoke(5,  "Starting Quinn Optimiser Toolkit...")
    $script:SetFoxSplash.Invoke(20, "Loading config...")
    if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction SilentlyContinue }

    $script:SetFoxSplash.Invoke(40, "Loading logging...")
    if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction SilentlyContinue }

    $script:SetFoxSplash.Invoke(65, "Loading engine...")
    if (-not (Test-Path $engineModule)) { throw "Engine module not found at $engineModule" }
    Import-Module $engineModule -Force -ErrorAction Stop

    $script:SetFoxSplash.Invoke(85, "Preparing UI...")
    $script:WriteLog.Invoke("Starting main window", "INFO")

    $startResult = $null
    try {
        $startResult = Start-QOTMain -RootPath $rootPath
    } catch {
        $script:WriteLog.Invoke(("Start-QOTMain failed: " + $_.Exception.Message), "ERROR")
        $script:WriteLog.Invoke(("Stack: " + $_.ScriptStackTrace), "ERROR")
        throw
    }

    $mw = Get-MainWindowFromResult -Result $startResult

    $startType = $(if ($startResult) { $startResult.GetType().FullName } else { "NULL" })
    $mwType    = $(if ($mw) { $mw.GetType().FullName } else { "NULL" })

    $script:WriteLog.Invoke(("Start-QOTMain returned type: " + $startType), "INFO")
    $script:WriteLog.Invoke(("Resolved main window type: " + $mwType), "INFO")

    $app = [System.Windows.Application]::Current
    if (-not $app) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnLastWindowClose
    }

    # Fallback if ContentRendered never fires
    $fallback = New-Object System.Windows.Threading.DispatcherTimer
    $fallback.Interval = [TimeSpan]::FromSeconds(5)

    $fallbackLocal = $fallback
    $fallback.Add_Tick( ({
        try { $fallbackLocal.Stop() } catch { }
        try { $script:CompleteIntro.Invoke("fallback") } catch { }
    }).GetNewClosure() )

    $fallback.Start()

    if ($mw) {
        try {
            $mw.Add_ContentRendered( ({
                try { $fallbackLocal.Stop() } catch { }
                try { $script:CompleteIntro.Invoke("contentrendered") } catch { }
            }).GetNewClosure() )
        } catch {
            $script:WriteLog.Invoke(("Failed to attach ContentRendered: " + $_.Exception.Message), "WARN")
        }

        try { if (-not $mw.IsVisible) { $mw.Show() } } catch { }

        try {
            [void]$app.Run()
        } catch {
            $script:WriteLog.Invoke(("App.Run failed: " + $_.Exception.Message), "ERROR")
            $script:WriteLog.Invoke(("Stack: " + $_.ScriptStackTrace), "ERROR")
            try { $script:CompleteIntro.Invoke("run-exception") } catch { }
        }
    }
    else {
        $script:WriteLog.Invoke("Main window could not be resolved. Skipping app loop.", "ERROR")
        try { $fallbackLocal.Stop() } catch { }
        try { $script:CompleteIntro.Invoke("mw-null") } catch { }
        try { $app.Shutdown() } catch { }
    }
}
finally {
    $WarningPreference = $oldWarningPreference
}
