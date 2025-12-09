# bootstrap.ps1
# Download the Quinn Optimiser Toolkit repo to a temp folder,
# load core modules, then hand off to Intro.ps1

param()

$ErrorActionPreference = "Stop"

# ------------------------------
# 1. Download / extract repo to TEMP
# ------------------------------
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

$repoOwner = "VoIyboo"
$repoName  = "Windows-Optimiser-Toolkit-"
$branch    = "main"

$baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
$zipPath   = Join-Path $baseTemp "repo.zip"
$extractTo = Join-Path $baseTemp "repo"

if (-not (Test-Path $baseTemp)) {
    New-Item -Path $baseTemp -ItemType Directory -Force | Out-Null
}

# Clean previous extract so we always get a fresh copy
if (Test-Path $extractTo) {
    Remove-Item $extractTo -Recurse -Force
}

$zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"

Write-Host "Downloading Quinn Optimiser Toolkit..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

# The extracted folder will look like 'Windows-Optimiser-Toolkit--main'
$rootFolder = Get-ChildItem -Path $extractTo | Select-Object -First 1
if (-not $rootFolder) {
    throw "Could not locate extracted repo folder under $extractTo"
}

$Global:QOT_Root = $rootFolder.FullName

Write-Host "Toolkit root: $Global:QOT_Root" -ForegroundColor Cyan

# ------------------------------
# 2. Import core modules from that root
# ------------------------------
$corePath      = Join-Path $Global:QOT_Root "src\Core"
$configModule  = Join-Path $corePath "Config\Config.psm1"
$loggingModule = Join-Path $corePath "Logging\Logging.psm1"
$engineModule  = Join-Path $corePath "Engine\Engine.psm1"

foreach ($mod in @($configModule, $loggingModule, $engineModule)) {
    if (-not (Test-Path $mod)) {
        throw "Core module not found: $mod"
    }
}

Import-Module $configModule  -Force
Import-Module $loggingModule -Force
Import-Module $engineModule  -Force

# ------------------------------
# 3. Configure config + logging
# ------------------------------
Initialize-QOTConfig

$logRoot = Get-QOTPath -Name Logs
Set-QLogRoot -Root $logRoot
Start-QLogSession

Write-QLog "Bootstrap initialised from TEMP copy."
Write-QLog "Toolkit root resolved as: $(Get-QOTRoot)"
Write-QLog "Version: $(Get-QOTVersion)"

# ------------------------------
# 4. Hand off to Intro.ps1 in the repo
# ------------------------------
$introPath = Join-Path $Global:QOT_Root "src\Intro\Intro.ps1"

if (-not (Test-Path $introPath)) {
    Write-Warning "Intro.ps1 not found at $introPath"
    Write-QLog "Intro.ps1 not found at $introPath"
} else {
    Write-Host "Launching Quinn Optimiser Toolkit..." -ForegroundColor Cyan
    Write-QLog "Launching Intro.ps1 from $introPath"

    & $introPath

    Write-QLog "Intro.ps1 completed. Bootstrap exiting."
}
