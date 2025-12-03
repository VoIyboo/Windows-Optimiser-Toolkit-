# Config.psm1

$Global:QOT_Config = @{
    Theme = "Dark"
    AccentColor = "#2563EB"
}

function Load-QConfig {
    Write-QLog "Config loaded."
}

function Get-QSetting {
    param([string]$Key)
    return $Global:QOT_Config[$Key]
}

Export-ModuleMember -Function Load-QConfig, Get-QSetting
