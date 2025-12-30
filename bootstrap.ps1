# bootstrap.ps1
# Remote bootstrap for: irm "<raw url>" | iex
# Downloads fresh repo zip into TEMP, extracts, runs Intro.ps1
# NEVER touches %LOCALAPPDATA%\StudioVoly\QuinnToolkit

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

$originalLocation = Get-Location

# -------------------------
# Logging
# -------------------------
$logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$bootstrapLog = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $bootstrapLog | Out-Null

try {
    # TLS
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {}

    # -------------------------
    # Repo info
    # -------------------------
    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    # -------------------------
    # TEMP workspace (code only)
    # -------------------------
    $baseTemp = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath  = Join-Path $baseTemp "repo.zip"

    if (Test-Path $baseTemp) {
        Remove-Item $baseTemp -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

    # Cache bust
    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip?cb=$cacheBust"

    Write-Host "Downloading Quinn Optimiser Toolkit..."
    Write-Host $zipUrl

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

    # -------------------------
    # Resolve extracted folder
    # -------------------------
    $rootFolder = Get-ChildItem $baseTemp -Directory |
        Where-Object { $_.Name -like "$repoName*" } |
        Select-Object -First 1

    if (-not $rootFolder) {
        throw "Could not locate extracted repo folder"
    }

    $toolkitRoot = $rootFolder.FullName
    $introPath   = Join-Path $toolkitRoot "src\Intro\Intro.ps1"

    if (-not (Test-Path $introPath)) {
        throw "Intro.ps1 not found"
    }

    $introLog = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    Write-Host ""
    Write-Host "Toolkit root: $toolkitRoot"
    Write-Host "Intro path:   $introPath"
    Write-Host "Intro log:    $introLog"
    Write-Host "Data folder:  $env:LOCALAPPDATA\StudioVoly\QuinnToolkit"
    Write-Host ""

    Set-Location $toolkitRoot

    # -------------------------
    # Launch WPF in Windows PowerShell (STA)
    # -------------------------
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $psExe -NoProfile -ExecutionPolicy Bypass -STA -File $introPath -LogPath $introLog
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework | Out-Null
        [System.Windows.MessageBox]::Show(
            "Bootstrap failed.`r`n$($_.Exception.Message)",
            "Quinn Optimiser Toolkit"
        ) | Out-Null
    } catch {}
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Set-Location $originalLocation
}
