# Config.psm1

. "$PSScriptRoot\Logging.psm1"

$Global:QOT_Config = @{
    Theme       = "Dark"
    AccentColor = "#2563EB"
}

function Load-QConfig {
    # Later you can load JSON/yaml here
    Write-QLog "Config loaded (defaults in memory)."
}

function Get-QSetting {
    param([string]$Key)
    return $Global:QOT_Config[$Key]
}

function Set-QSetting {
    param(
        [string]$Key,
        [object]$Value
    )
    $Global:QOT_Config[$Key] = $Value
}

Export-ModuleMember -Function Load-QConfig, Get-QSetting, Set-QSetting
