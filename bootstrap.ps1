# bootstrap.ps1
# Always download a fresh build, extract clean, run Intro.ps1 quietly

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

$logPath = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $logPath -Append | Out-Null

try {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

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
    $introPath   = Join-Path $toolkitRoot "src\Intro\Intro.ps1"

    if (-not (Test-Path -LiteralPath $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    Set-Location -LiteralPath $toolkitRoot
    & $introPath -LogPath $logPath -Quiet | Out-Null
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
