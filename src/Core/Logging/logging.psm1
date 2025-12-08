# Logging.psm1
# Centralised logging utility for the Quinn Optimiser Toolkit

# Module-level variables
$script:QLogRoot = $null
$script:QLogFile = $null
$script:QLogSessionActive = $false

# Set the root folder where logs will be written
function Set-QLogRoot {
    param (
        [string]$Root
    )

    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $script:QLogRoot = $Root
    $script:QLogFile = Join-Path $script:QLogRoot "QuinnOptimiserToolkit.log"
}

# Start a new logging session
function Start-QLogSession {
    if (-not $script:QLogFile) {
        throw "QLog root not set. Call Set-QLogRoot first."
    }

    $script:QLogSessionActive = $true
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $script:QLogFile -Value "===== Logging session started at $timestamp ====="
}

# Core logging function
function Write-QLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    if (-not $script:QLogSessionActive) {
        return
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    Add-Content -Path $script:QLogFile -Value $line
}

# Allow other modules to query where logs are stored
function Get-QLogPath {
    param (
        [string]$Name
    )

    switch ($Name) {
        "Root" { return $script:QLogRoot }
        "File" { return $script:QLogFile }
        default { return $script:QLogRoot }
    }
}

Export-ModuleMember -Function `
    Set-QLogRoot, `
    Start-QLogSession, `
    Write-QLog, `
    Get-QLogPath
