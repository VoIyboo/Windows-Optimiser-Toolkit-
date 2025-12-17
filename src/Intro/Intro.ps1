# Intro.ps1
# Shows splash immediately, runs init in background, then opens main window

[CmdletBinding()]
param(
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# --- Resolve toolkit root (Intro.ps1 is in src\Intro) ---
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# --- Load core logging early (so we can log during init) ---
$logging = Join-Path $toolkitRoot "src\Core\Logging\Logging.psm1"
if (Test-Path $logging) { Import-Module $logging -Force -ErrorAction SilentlyContinue }

try { Write-QLog "Intro: starting. Root=$toolkitRoot" } catch { }

# --- WPF assemblies ---
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function New-QOTSplashWindow {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Studio Voly"
        Width="620" Height="320"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        Topmost="True"
        ShowInTaskbar="False">
    <Border Background="#0B1220" CornerRadius="20" BorderBrush="#111827" BorderThickness="1" Padding="22">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock Text="Studio Voly" Foreground="#E5E7EB" FontSize="34" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                <TextBlock x:Name="TxtStatus" Text="Starting..." Foreground="#9CA3AF" FontSize="13" Margin="0,10,0,0" HorizontalAlignment="Center"/>
            </StackPanel>

            <ProgressBar Grid.Row="1"
                         x:Name="Bar"
                         Height="14"
                         Margin="0,18,0,0"
                         Minimum="0" Maximum="100"
                         Value="0"
                         Foreground="#22C55E"
                         Background="#111827"/>

            <TextBlock Grid.Row="2"
                       x:Name="TxtPercent"
                       Text="0%"
                       Foreground="#9CA3AF"
                       FontSize="11"
                       Margin="0,10,0,0"
                       HorizontalAlignment="Center"/>
        </Grid>
    </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

function Set-Splash {
    param(
        [Parameter(Mandatory)] $Window,
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [int]$Percent
    )

    $Window.Dispatcher.Invoke([action]{
        $txt = $Window.FindName("TxtStatus")
        $bar = $Window.FindName("Bar")
        $pct = $Window.FindName("TxtPercent")

        if ($txt) { $txt.Text = $Text }
        if ($bar) { $bar.Value = [Math]::Max(0, [Math]::Min(100, $Percent)) }
        if ($pct) { $pct.Text = ("{0}%" -f $Percent) }
    })
}

# Create splash and show it immediately
$splash = New-QOTSplashWindow
$splash.Show()

Set-Splash -Window $splash -Text "Loading core..." -Percent 5

# --- Background init: do NOT block UI thread ---
$ps = [PowerShell]::Create()
$null = $ps.AddScript({
    param($Root)

    $ErrorActionPreference = "Stop"

    # Import Engine first (it will import modules)
    $engine = Join-Path $Root "src\Core\Engine\Engine.psm1"
    if (-not (Test-Path $engine)) { throw "Engine.psm1 missing at $engine" }
    Import-Module $engine -Force -ErrorAction Stop

    # Optional: warm up data (avoid UI feeling “empty” on first click)
    if (Get-Command Refresh-QOTInstalledAppsGrid -ErrorAction SilentlyContinue) {
        try { Write-QLog "Intro init: warm installed apps scan (background)"; } catch { }
        # We only warm data structures here. UI wiring will bind later.
        Refresh-QOTInstalledAppsGrid -Grid $null 2>$null
    }

    if (Get-Command Refresh-QOTCommonAppsGrid -ErrorAction SilentlyContinue) {
        try { Write-QLog "Intro init: warm common apps list (background)"; } catch { }
        Refresh-QOTCommonAppsGrid -Grid $null 2>$null
    }

    return $true
}).AddArgument($toolkitRoot)

$async = $ps.BeginInvoke()

# Simple progress loop while background init runs
$progress = 10
while (-not $async.IsCompleted) {
    $progress = [Math]::Min(90, $progress + 2)
    Set-Splash -Window $splash -Text "Loading modules..." -Percent $progress
    Start-Sleep -Milliseconds 120
}

try {
    $result = $ps.EndInvoke($async)
    Set-Splash -Window $splash -Text "Opening app..." -Percent 100
}
catch {
    try { Write-QLog ("Intro init failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }

    [System.Windows.MessageBox]::Show(
        "Startup failed:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        "OK",
        "Error"
    ) | Out-Null

    $splash.Close()
    return
}
finally {
    $ps.Dispose()
}

# Close splash, then open main window (same thread)
Start-Sleep -Milliseconds 200
$splash.Close()

# Call into Engine entry point
try {
    Start-QOTMain -RootPath $toolkitRoot
}
catch {
    try { Write-QLog ("Start-QOTMain failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    [System.Windows.MessageBox]::Show(
        "Failed to launch main UI:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        "OK",
        "Error"
    ) | Out-Null
}
