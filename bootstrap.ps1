# bootstrap.ps1
# Download latest Quinn Optimiser Toolkit build to a temp folder and run Intro.ps1

$ErrorActionPreference  = "Stop"
$ProgressPreference     = "SilentlyContinue"
$WarningPreference      = "SilentlyContinue"
$VerbosePreference      = "SilentlyContinue"
$InformationPreference  = "SilentlyContinue"

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

    $baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath   = Join-Path $baseTemp "repo.zip"

    # Keep it quiet but logged
    try { Write-QLog "Bootstrap starting. Temp=$baseTemp" "INFO" } catch { }

    # Clean temp every run so we never read stale folders
    if (Test-Path -LiteralPath $baseTemp) {
        Remove-Item -LiteralPath $baseTemp -Recurse -Force
    }
    New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"

    # Download
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing | Out-Null

    # Extract
    Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

    # Find extracted root folder (GitHub names it like RepoName-branch)
    $toolkitRootFolder = Get-ChildItem -LiteralPath $baseTemp -Directory |
        Where-Object { $_.Name -like "$repoName*" } |
        Select-Object -First 1

    if (-not $toolkitRootFolder) {
        # Fallback: first directory under temp
        $toolkitRootFolder = Get-ChildItem -LiteralPath $baseTemp -Directory | Select-Object -First 1
    }

    if (-not $toolkitRootFolder) {
        throw "Could not locate extracted repo folder under $baseTemp"
    }

    $toolkitRoot = $toolkitRootFolder.FullName

    $introPath = Join-Path $toolkitRoot "src\Intro\Intro.ps1"
    if (-not (Test-Path -LiteralPath $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    Set-Location -LiteralPath $toolkitRoot

    # Run intro quietly (splash handles UI)
    & $introPath -LogPath $logPath -Quiet | Out-Null
}
catch {
    # Ensure errors still end up in log
    Write-Host $_.Exception.ToString()
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
