# bootstrap.ps1
# Dev friendly launcher
# Default: run local repo copy (same folder as this bootstrap)
# Optional: download fresh from GitHub into TEMP and run that copy

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
    # Mode
    # -------------------------
    # Local  = run from the repo on disk (recommended while developing)
    # Remote = download fresh build from GitHub into TEMP (good for release testing)
    $RunMode = "Local"

    # -------------------------
    # Resolve toolkit root
    # -------------------------
    $toolkitRoot = $null

    if ($RunMode -eq "Local") {
        # Use the folder this bootstrap.ps1 lives in
        $toolkitRoot = Split-Path -Parent $PSCommandPath

        # Safety: if bootstrap sits in a subfolder, walk up until we find src\Intro\Intro.ps1
        $maxUp = 5
        for ($i = 0; $i -lt $maxUp; $i++) {
            $tryIntro = Join-Path $toolkitRoot "src\Intro\Intro.ps1"
            if (Test-Path -LiteralPath $tryIntro) { break }
            $parent = Split-Path -Parent $toolkitRoot
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $toolkitRoot) { break }
            $toolkitRoot = $parent
        }
    }
    else {
        # Remote mode
        $repoOwner = "VoIyboo"
        $repoName  = "Windows-Optimiser-Toolkit-"
        $branch    = "main"

        $baseTemp = Join-Path $env:TEMP "QuinnOptimiserToolkit"
        $zipPath  = Join-Path $baseTemp "repo.zip"

        if (Test-Path -LiteralPath $baseTemp) {
            Remove-Item -LiteralPath $baseTemp -Recurse -Force
        }
        New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

        $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip?cb=$cacheBust"

        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ "Cache-Control"="no-cache" } -UseBasicParsing | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

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
    }

    if (-not $toolkitRoot) {
        throw "Toolkit root could not be resolved."
    }

    $introPath = Join-Path $toolkitRoot "src\Intro\Intro.ps1"
    if (-not (Test-Path -LiteralPath $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    $introLog = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    Set-Location -LiteralPath $toolkitRoot

    Write-Host ""
    Write-Host "Run mode:     $RunMode"
    Write-Host "Toolkit root: $toolkitRoot"
    Write-Host "Intro path:   $introPath"
    Write-Host "Intro log:    $introLog"
    Write-Host "Bootstrap log:$bootstrapLog"
    Write-Host ""

    # Always run WPF in Windows PowerShell (STA)
    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    & $psExe -NoProfile -ExecutionPolicy Bypass -STA -File $introPath -LogPath $introLog
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
