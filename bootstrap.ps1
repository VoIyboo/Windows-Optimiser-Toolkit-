# bootstrap.ps1
# Downloads the latest copy of the repo to %TEMP% and launches Version 2.7

param()

$ErrorActionPreference = "Stop"

# Make sure TLS 1.2 is enabled for GitHub
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

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

Write-Host "Downloading Quinn Optimiser Toolkit (v2.7 base)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

# The extracted folder will be "Windows-Optimiser-Toolkit--main"
$rootFolder = Get-ChildItem -Path $extractTo | Select-Object -First 1
if (-not $rootFolder) {
    throw "Could not locate extracted repo folder under $extractTo"
}

$Global:QOT_Root = $rootFolder.FullName

$corePath = Join-Path $Global:QOT_Root "src\Core"

# Import core modules
Import-Module (Join-Path $corePath "Logging.psm1") -Force
Import-Module (Join-Path $corePath "Config.psm1")  -Force
Import-Module (Join-Path $corePath "Engine.psm1")  -Force

# Configure logging root under ProgramData
$logRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
Set-QLogRoot -Root $logRoot

Write-QLog "Bootstrap started. Root: $Global:QOT_Root  Version: $Global:QOT_Version"


function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-QLog "[$Level] $Message"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Start Version 2.7 (legacy script)
Start-QOTLegacy -RootPath $Global:QOT_Root
