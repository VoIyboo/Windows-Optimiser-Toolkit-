# Logging.psm1

$Global:QOT_LogRoot = "$env:TEMP\QuinnToolkitLogs"
if (-not (Test-Path $Global:QOT_LogRoot)) {
    New-Item -Path $Global:QOT_LogRoot -ItemType Directory | Out-Null
}

function Set-QLogRoot {
    param([string]$Root)
    if (Test-Path $Root) {
        $Global:QOT_LogRoot = $Root
    }
}

function Write-QLog {
    param([string]$Message, [string]$Level = "INFO")

    $logFile = Join-Path $Global:QOT_LogRoot "Toolkit.log"
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    Add-Content -Path $logFile -Value "[$timestamp] [$Level] $Message"
}

Export-ModuleMember -Function Write-QLog, Set-QLogRoot
