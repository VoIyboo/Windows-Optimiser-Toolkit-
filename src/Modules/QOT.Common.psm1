# QOT.Common.psm1

$script:ToolkitRoot = "C:\IT"
if (-not (Test-Path $script:ToolkitRoot)) {
    New-Item -Path $script:ToolkitRoot -ItemType Directory -Force | Out-Null
}
$script:LogFile = Join-Path $script:ToolkitRoot "QuinnOptimiserToolkit.log"

function Get-QOTLogPath {
    $script:LogFile
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $script:LogFile -Value ("[{0}] [{1}] {2}" -f $timestamp, $Level, $Message)
}

function Set-Status {
    param(
        [string]$Text,
        [int]$Progress = 0,
        [bool]$Busy = $false
    )

    if ($script:StatusLabel) { $script:StatusLabel.Text = $Text }
    if ($script:MainProgress) {
        $script:MainProgress.Value = $Progress
        $script:MainProgress.IsIndeterminate = $Busy
    }

    foreach ($btn in @($script:RunButton, $script:BtnScanApps, $script:BtnUninstallSelected)) {
        if ($btn) {
            $btn.IsEnabled = -not $Busy
        }
    }
}

function Get-SystemSummaryText {
    $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    if (-not $drive) { return "C drive: not found" }

    $totalBytes = $drive.Used + $drive.Free
    if ($totalBytes -le 0) {
        return "C: capacity could not be calculated"
    }

    $usedGB  = [math]::Round($drive.Used  / 1GB, 1)
    $freeGB  = [math]::Round($drive.Free  / 1GB, 1)
    $totalGB = [math]::Round($totalBytes  / 1GB, 1)
    $freePct = [math]::Round(($drive.Free / $totalBytes) * 100, 1)

    "C: $usedGB GB used / $freeGB GB free ($totalGB GB total, $freePct% free)"
}

Export-ModuleMember -Function Write-Log, Set-Status, Get-SystemSummaryText, Get-QOTLogPath

