# bootstrap.ps1
# Remote bootstrap for: irm "<raw url>" | iex
# Downloads fresh zip into TEMP, extracts clean, runs Intro.ps1 in Windows PowerShell (STA)
# NOTE: Only deletes TEMP extraction folder, never touches %LOCALAPPDATA%\StudioVoly\QuinnToolkit

$ErrorActionPreference   = "Stop"
$ProgressPreference      = "SilentlyContinue"
$WarningPreference       = "SilentlyContinue"
$VerbosePreference       = "SilentlyContinue"
$InformationPreference   = "SilentlyContinue"

$originalLocation = Get-Location

$logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$bootstrapLog = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $bootstrapLog -Append | Out-Null

try {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    # Optional: minimise current PowerShell window (no here-string, safe in one-line too)
    try {
        $cs = 'using System; using System.Runtime.InteropServices; public static class NativeMethods { [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); }'
        Add-Type -TypeDefinition $cs -ErrorAction SilentlyContinue | Out-Null
        $psWindowHandle = [IntPtr](Get-Process -Id $PID).MainWindowHandle
        if ($psWindowHandle -ne [IntPtr]::Zero) {
            [NativeMethods]::ShowWindow($psWindowHandle, 6) | Out-Null
        }
    } catch { }

    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    $baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath   = Join-Path $baseTemp "repo.zip"

    # Wipe TEMP only (code cache), never user data
    if (Test-Path -LiteralPath $baseTemp) {
        Remove-Item -LiteralPath $baseTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip?cb=$cacheBust"

    Write-Host ""
    Write-Host "Downloading Quinn Optimiser Toolkit..." -ForegroundColor Cyan
    Write-Host "URL: $zipUrl"
    Write-Host ""

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ "Cache-Control"="no-cache" } -UseBasicParsing | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

    # Extracted folder name is usually like Windows-Optimiser-Toolkit--main
    $rootFolder = Get-ChildItem -LiteralPath $baseTemp -Directory |
        Where-Object { $_.Name -like "$repoName*" } |
        Select-Object -First 1

    if (-not $rootFolder) {
        $rootFolder = Get-ChildItem -LiteralPath $baseTemp -Directory | Select-Object -First 1
    }
    if (-not $rootFolder) {
        throw "Could not locate extracted repo folder under $baseTemp"
    }

    $toolkitRoot = $rootFolder.FullName
    $introPath   = Join-Path $toolkitRoot "src\Intro\Intro.ps1"

    if (-not (Test-Path -LiteralPath $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    $introLog = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    Write-Host "Toolkit root:  $toolkitRoot"
    Write-Host "Intro path:    $introPath"
    Write-Host "Intro log:     $introLog"
    Write-Host "Bootstrap log: $bootstrapLog"
    Write-Host "Data folder:   $($env:LOCALAPPDATA)\StudioVoly\QuinnToolkit (not touched)"
    Write-Host ""

    Set-Location -LiteralPath $toolkitRoot

    # Always run WPF in Windows PowerShell (STA)
    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    & $psExe -NoProfile -ExecutionPolicy Bypass -STA -File $introPath -LogPath $introLog
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        [System.Windows.MessageBox]::Show("Bootstrap failed.`r`n$($_.Exception.Message)","Quinn Optimiser Toolkit") | Out-Null
    } catch { }
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
