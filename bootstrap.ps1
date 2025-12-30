# bootstrap.ps1
# Remote-first bootstrap designed for: irm "<raw url>" | iex
# Downloads fresh repo zip into TEMP, extracts clean, runs Intro.ps1 in Windows PowerShell (STA)

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
    # Temp workspace
    # -------------------------
    $baseTemp = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath  = Join-Path $baseTemp "repo.zip"

    # Always wipe to avoid stale ghost copies
    if (Test-Path -LiteralPath $baseTemp) {
        try {
            Remove-Item -LiteralPath $baseTemp -Recurse -Force -ErrorAction Stop
        } catch {
            # If something is holding a file, use a unique folder as a fallback
            $baseTemp = Join-Path $env:TEMP ("QuinnOptimiserToolkit_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
            $zipPath  = Join-Path $baseTemp "repo.zip"
        }
    }
    New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

    # Cache bust to force a fresh zip
    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip?cb=$cacheBust"

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ "Cache-Control"="no-cache" } -UseBasicParsing | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

    # Resolve extracted root folder
    $rootFolder = Get-ChildItem -LiteralPath $baseTemp -Directory |
        Where-Object { $_.Name -like "$repoName*" }
