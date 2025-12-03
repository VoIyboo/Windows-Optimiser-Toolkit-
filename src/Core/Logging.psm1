# Logging.psm1

$Global:QOT_LogRoot = "$env:TEMP\QuinnToolkitLogs"
if (-not (Test-Path $Global:QOT_LogRoot)) {
    New-Item -Path $Global:QOT_LogRoot -ItemType Directory | Out-Null
}

function Set-QLogRoot {
    param([string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) { return }
    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }
    $Global:QOT_LogRoot = $Root
}

function Write-QLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logFile   = Join-Path $Global:QOT_LogRoot "Toolkit.log"
    Add-Content -Path $logFile -Value "[$timestamp] [$Level] $Message"
}

Export-ModuleMember -Function Write-QLog, Set-QLogRoot
