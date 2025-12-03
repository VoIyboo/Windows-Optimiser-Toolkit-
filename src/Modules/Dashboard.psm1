. "$PSScriptRoot\..\Core\Logging.psm1"

function Get-QSystemHealth {
    Write-QLog "System health requested (stub)."

    [pscustomobject]@{
        CPUUsage   = "3 %"
        RAMUsage   = "27 %"
        DiskUsage  = "55 %"
        TempFolder = "1.2 GB"
    }
}

Export-ModuleMember -Function Get-QSystemHealth

