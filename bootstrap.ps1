# bootstrap.ps1
# Remote-first bootstrap for: irm "<raw url>" | iex
# Downloads fresh repo zip into TEMP, extracts clean, runs Intro.ps1 in Windows PowerShell (STA)
# IMPORTANT: Only deletes the TEMP extraction folder, never touches user data in %LOCALAPPDATA%\StudioVoly\QuinnToolkit

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

    # -------------------------
    # Repo settings
    # -------------------------
    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    # -------------------------
    # TEMP workspace
    # -------------------------
    $baseTemp = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath  = Join-Path $baseTemp "repo.zip"

    # Always wipe TEMP extraction folder to avoid stale code
    if (Test-Path -LiteralPath $baseTemp) {
        try {
            Remove-Item -LiteralPath $baseTemp -Recurse -Force -ErrorAction Stop
        } catch {
            # Fallback if something locks the folder
            $baseTemp = Join-Path $env:TEMP ("QuinnOptimiserToolkit_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
            $zipPath  = Join-Path $baseTemp "repo.zip"
        }
    }
    New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

    # Cache bust so GitHub returns a fresh zip
    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip?cb=$cacheBust"

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ "Cache-Control"="no-cache" } -UseBasicParsing | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

    # Locate extracted repo root
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

    Set-Location -LiteralPath $toolkitRoot

    Write-Host ""
    Write-Host "Toolkit root:  $toolkitRoot"
    Write-Host "Intro path:    $introPath"
    Write-Host "Intro log:     $introLog"
    Write-Host "Bootstrap log: $bootstrapLog"
    Write-Host "Data folder:   $($env:LOCALAPPDATA)\StudioVoly\QuinnToolkit (not touched)"
    Write-Host ""

    # Always run WPF in Windows PowerShell (STA)
    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    & $psExe -NoProfile -ExecutionPolicy Bypass -STA -File $introPath -LogPath $introLog
}
catch {
    try {
        $msg = $_.Exception.Message
        [System.Windows.MessageBox]::Show("Bootstrap failed.`r`n$msg","Quinn Optimiser Toolkit") | Out-Null
    } catch { }

    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
