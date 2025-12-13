# bootstrap.ps1
# Download latest Quinn Optimiser Toolkit build to a temp folder and run Intro.ps1

$ErrorActionPreference = "Stop"

# Remember where the user started
$originalLocation = Get-Location

# Win32 helper to control the PowerShell window
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeMethods
{
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# Try to get the current PowerShell host window and minimise it
$psWindowHandle = [IntPtr](Get-Process -Id $PID).MainWindowHandle
if ($psWindowHandle -ne [IntPtr]::Zero) {
    # 6 = SW_MINIMISE
    [NativeMethods]::ShowWindow($psWindowHandle, 6);
}

# Temp working folder
$baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
$zipPath   = Join-Path $baseTemp "repo.zip"
$extractTo = Join-Path $baseTemp "repo"

# Splash signalling
$signalPath    = Join-Path $env:TEMP "QOT_ready.signal"
$splashHostTmp = Join-Path $baseTemp "SplashHost.ps1"

# Ensure temp folder exists
if (-not (Test-Path $baseTemp)) {
    New-Item -Path $baseTemp -ItemType Directory -Force | Out-Null
}

# Make sure any old signal is gone
try { Remove-Item -LiteralPath $signalPath -Force -ErrorAction SilentlyContinue } catch { }

# Write a temporary splash host so the splash can appear immediately
@'
param(
    [Parameter(Mandatory)]
    [string]$SignalPath,

    [string]$Title = "Quinn Optimiser Toolkit",
    [string]$Subtitle = "Loading..."
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        Width="520"
        Height="220"
        Topmost="True"
        ShowInTaskbar="False">
  <Border CornerRadius="16" Background="#0F172A" BorderBrush="#374151" BorderThickness="1" Padding="18">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
        <TextBlock Text="$Title" Foreground="White" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock Text="$Subtitle" Foreground="#9CA3AF" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>

      <Border Grid.Row="1" Margin="0,18,0,10" Background="#020617" CornerRadius="12" BorderBrush="#374151" BorderThickness="1">
        <Grid Margin="12">
          <ProgressBar IsIndeterminate="True" Height="18"/>
          <TextBlock Text="Starting up..." Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="12"/>
        </Grid>
      </Border>

      <TextBlock Grid.Row="2" Text="Studio Voly" Foreground="#9CA3AF" FontSize="11" HorizontalAlignment="Right"/>
    </Grid>
  </Border>
</Window>
"@

$xml    = [xml]$xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$win    = [Windows.Markup.XamlReader]::Load($reader)

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    if (Test-Path -LiteralPath $SignalPath) {
        $timer.Stop()
        try { Remove-Item -LiteralPath $SignalPath -Force -ErrorAction SilentlyContinue } catch {}
        $win.Close()
    }
})
$timer.Start()

$null = $win.ShowDialog()
'@ | Set-Content -Path $splashHostTmp -Encoding UTF8

# Launch splash immediately
Start-Process powershell `
    -ArgumentList "-NoProfile -STA -File `"$splashHostTmp`" -SignalPath `"$signalPath`"" `
    -WindowStyle Hidden

try {
    # Make sure TLS 1.2 is enabled for GitHub
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    # Clean old extract
    if (Test-Path $extractTo) {
        Remove-Item $extractTo -Recurse -Force
    }

    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"

    Write-Host "Downloading Quinn Optimiser Toolkit..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    Write-Host "Extracting..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

    # The extracted folder will be "Windows-Optimiser-Toolkit--main"
    $rootFolder = Get-ChildItem -Path $extractTo | Select-Object -First 1
    if (-not $rootFolder) {
        throw "Could not locate extracted repo folder under $extractTo"
    }

    $toolkitRoot = $rootFolder.FullName
    Write-Host "Toolkit root: $toolkitRoot"

    # Path to Intro.ps1 inside the extracted repo
    $introPath = Join-Path $toolkitRoot "src\Intro\Intro.ps1"
    if (-not (Test-Path $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    # Change location to the toolkit root so relative paths in Intro.ps1 work
    Set-Location $toolkitRoot

    # Hand off to the Intro script
    & $introPath
}
finally {
    # Always close splash, even on failure
    try { New-Item -ItemType File -Path $signalPath -Force | Out-Null } catch { }

    # Always restore location
    Set-Location $originalLocation

    # Restore the PowerShell window if we managed to minimise it
    if ($psWindowHandle -ne [IntPtr]::Zero) {
        # 9 = SW_RESTORE
        [NativeMethods]::ShowWindow($psWindowHandle, 9);
    }
}
