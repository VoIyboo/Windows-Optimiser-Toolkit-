# Config.psm1
# Basic config / version info

$Global:QOT_Version = "2.7.0"

function Get-QConfig {
    [pscustomobject]@{
        Version = $Global:QOT_Version
    }
}

Export-ModuleMember -Variable QOT_Version -Function Get-QConfig
