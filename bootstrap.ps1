# bootstrap.ps1
# Download latest Quinn Optimiser Toolkit build to a temp folder and run Intro.ps1

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

Write-Host "Downloading Quinn Optimiser Toolkit..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

# The extracted folder will be "Windows-Optimiser-Toolkit--main"
$rootFolder = Get-ChildItem -Path $extractTo | Select-Object -First 1
if (-not $rootFolder) {
    throw "Could not locate extracted repo folder under $extractTo"
}

$Global:QOT_Root = $rootFolder.FullName
Write-Host "Toolkit root: $Global:QOT_Root"

# Path to Intro.ps1 inside the extracted repo
$introPath = Join-Path $Global:QOT_Root "src\Intro\Intro.ps1"

if (-not (Test-Path $introPath)) {
    throw "Intro.ps1 not found at $introPath"
}

# Hand off to the Intro script (which loads Config / Logging / Engine)
& $introPath
