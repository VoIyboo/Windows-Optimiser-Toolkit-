# bootstrap.ps1
# Download latest Quinn Optimiser Toolkit build to a temp folder and run Intro.ps1

$ErrorActionPreference   = "Stop"
$ProgressPreference     = "SilentlyContinue"
$WarningPreference      = "SilentlyContinue"
$VerbosePreference      = "SilentlyContinue"
$InformationPreference  = "SilentlyContinue"

$originalLocation = Get-Location

$logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logPath = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $logPath -Append | Out-Null

try {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    $baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath   = Join-Path $baseTemp "repo.zip"
    $extractTo = Join-Path $baseTemp "repo"

    if (-not (Test-Path $baseTemp)) {
        New-Item -Path $baseTemp -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $extractTo) {
        Remove-Item $extractTo -Recurse -Force
    }

    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"

    $rootFolder = Get-ChildItem -Path $extractTo | Select-Object -First 1
    if (-not $rootFolder) {
        throw "Could not locate extracted repo folder under $extractTo"
    }

    $introPath = Join-Path $toolkitRoot "src\Intro\Intro.ps1"
    if (-not (Test-Path $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    Set-Location $toolkitRoot

    & $introPath -LogPath $logPath -Quiet
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
