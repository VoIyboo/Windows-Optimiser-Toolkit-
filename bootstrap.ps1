# bootstrap.ps1
# Download latest Quinn Optimiser Toolkit build to a temp folder and run Intro.ps1

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
$WarningPreference  = 'SilentlyContinue'
$VerbosePreference  = 'SilentlyContinue'

# Remember where the user started
$originalLocation = Get-Location

$logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logPath = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

Start-Transcript -Path $logPath -Append | Out-Null


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

try {
    # Make sure TLS 1.2 is enabled for GitHub
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    # Temp working folder
    $baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath   = Join-Path $baseTemp "repo.zip"
    $extractTo = Join-Path $baseTemp "repo"

    if (-not (Test-Path $baseTemp)) {
        New-Item -Path $baseTemp -ItemType Directory -Force | Out-Null
    }

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

    # Hand off to the Intro script (this shows the Studio Voly splash)
    & $introPath -LogPath $logPath -Quiet
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    # Always restore the user's original prompt location
    Set-Location $originalLocation
}
