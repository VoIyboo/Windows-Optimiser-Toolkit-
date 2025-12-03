# Logging.psm1
# Simple central logging for the toolkit

$Global:QOT_LogRoot = $null

function Set-QLogRoot {
    param(
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { return }

    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $Global:QOT_LogRoot = $Root
}

function Write-QLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    try {
        if (-not $Global:QOT_LogRoot) { return }

        $logFile   = Join-Path $Global:QOT_LogRoot "QuinnOptimiserToolkit.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line      = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
        Add-Content -Path $logFile -Value $line
    } catch {
        # Logging should never crash anything
    }
}

Export-ModuleMember -Variable QOT_LogRoot -Function Set-QLogRoot, Write-QLog
