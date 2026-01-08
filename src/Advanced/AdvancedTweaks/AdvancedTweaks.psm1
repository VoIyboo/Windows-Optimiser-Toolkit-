# AdvancedTweaks.psm1
# Advanced system and app tweaks (independent from Tweaks & Cleaning)

Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force

function Set-QOTRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord"
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-QLog ("Advanced tweak: set {0}\\{1} = {2}" -f $Path, $Name, $Value)
        return $true
    }
    catch {
        Write-QLog ("Advanced tweak failed to set {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
        return $false
    }
}

function Add-QOTHostsEntries {
    param(
        [Parameter(Mandatory)][string[]]$Domains
    )

    $hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"

    try {
        if (-not (Test-Path -LiteralPath $hostsPath)) {
            Write-QLog "Hosts file not found; cannot add entries." "ERROR"
            return $false
        }

        $content = Get-Content -LiteralPath $hostsPath -ErrorAction Stop
        $added = $false

        foreach ($domain in $Domains) {
            if ($content -match "\b$([Regex]::Escape($domain))\b") { continue }

            Add-Content -LiteralPath $hostsPath -Value ("0.0.0.0 {0} # QOT" -f $domain)
            $added = $true
        }

        if ($added) {
            Write-QLog "Advanced tweak: hosts entries added." "INFO"
        } else {
            Write-QLog "Advanced tweak: hosts entries already present." "INFO"
        }

        return $true
    }
    catch {
        Write-QLog ("Advanced tweak failed to update hosts file: {0}" -f $_.Exception.Message) "ERROR"
        return $false
    }
}

function Add-QOTFirewallBlockRule {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$ProgramPath
    )

    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-QLog "Advanced tweak: New-NetFirewallRule not available." "ERROR"
        return $false
    }

    if (-not (Test-Path -LiteralPath $ProgramPath)) {
        Write-QLog ("Advanced tweak: program not found for firewall block: {0}" -f $ProgramPath) "WARN"
        return $false
    }

    try {
        $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-QLog ("Advanced tweak: firewall rule already exists: {0}" -f $DisplayName)
            return $true
        }

        New-NetFirewallRule -DisplayName $DisplayName -Direction Outbound -Program $ProgramPath -Action Block | Out-Null
        Write-QLog ("Advanced tweak: firewall rule created: {0}" -f $DisplayName)
        return $true
    }
    catch {
        Write-QLog ("Advanced tweak failed to create firewall rule {0}: {1}" -f $DisplayName, $_.Exception.Message) "ERROR"
        return $false
    }
}

function Invoke-QAdvancedAdobeNetworkBlock {
    $domains = @(
        "activate.adobe.com",
        "practivate.adobe.com",
        "lm.licenses.adobe.com",
        "na1r.services.adobe.com",
        "cc-api-data.adobe.io"
    )

    Add-QOTHostsEntries -Domains $domains | Out-Null

    $firewallTargets = @(
        "$env:ProgramFiles\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe",
        "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\ADS\Adobe Desktop Service.exe",
        "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\CEF\Adobe CEF Helper.exe"
    )

    foreach ($target in $firewallTargets) {
        Add-QOTFirewallBlockRule -DisplayName ("QOT Block Adobe: {0}" -f [System.IO.Path]::GetFileName($target)) -ProgramPath $target | Out-Null
    }
}

function Invoke-QAdvancedBlockRazerInstalls {
    $domains = @(
        "installer.razerzone.com",
        "drivers.razersupport.com",
        "rzr.to"
    )

    Add-QOTHostsEntries -Domains $domains | Out-Null
}

function Invoke-QAdvancedBraveDebloat {
    $path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

    Set-QOTRegistryValue -Path $path -Name "BraveRewardsDisabled" -Value 1 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "BraveWalletDisabled" -Value 1 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "TorDisabled" -Value 1 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "BackgroundModeEnabled" -Value 0 | Out-Null
}

function Invoke-QAdvancedEdgeDebloat {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    Set-QOTRegistryValue -Path $path -Name "HideFirstRunExperience" -Value 1 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "StartupBoostEnabled" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "BackgroundModeEnabled" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "PromotionalTabsEnabled" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "ShowRecommendationsEnabled" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "EdgeShoppingAssistantEnabled" -Value 0 | Out-Null
}

function Invoke-QAdvancedDisableEdge {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    Set-QOTRegistryValue -Path $path -Name "AllowMicrosoftEdgeLaunchOnStartup" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "AllowPrelaunch" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "StartupBoostEnabled" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "BackgroundModeEnabled" -Value 0 | Out-Null
}

function Invoke-QAdvancedEdgeUninstallable {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    Set-QOTRegistryValue -Path $path -Name "UninstallAllowed" -Value 1 | Out-Null
}

function Invoke-QAdvancedDisableBackgroundApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"

    Set-QOTRegistryValue -Path $path -Name "GlobalUserDisabled" -Value 1 | Out-Null
}

function Invoke-QAdvancedDisableFullscreenOptimizations {
    $path = "HKCU:\System\GameConfigStore"

    Set-QOTRegistryValue -Path $path -Name "GameDVR_FSEBehaviorMode" -Value 2 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 | Out-Null
}

function Invoke-QAdvancedDisableIPv6 {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"

    Set-QOTRegistryValue -Path $path -Name "DisabledComponents" -Value 255 | Out-Null
}

function Invoke-QAdvancedDisableTeredo {
    try {
        & netsh interface teredo set state disabled | Out-Null
        Write-QLog "Advanced tweak: Teredo disabled."
    }
    catch {
        Write-QLog ("Advanced tweak failed to disable Teredo: {0}" -f $_.Exception.Message) "ERROR"
    }
}

function Invoke-QAdvancedDisableCopilot {
    $pathMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    $pathUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"

    Set-QOTRegistryValue -Path $pathMachine -Name "TurnOffWindowsCopilot" -Value 1 | Out-Null
    Set-QOTRegistryValue -Path $pathUser -Name "TurnOffWindowsCopilot" -Value 1 | Out-Null
}

function Invoke-QAdvancedDisableStorageSense {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"

    Set-QOTRegistryValue -Path $path -Name "01" -Value 0 | Out-Null
    Set-QOTRegistryValue -Path $path -Name "StorageSenseEnabled" -Value 0 | Out-Null
}

function Invoke-QAdvancedDisableNotificationTray {
    $policyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    $legacyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

    Set-QOTRegistryValue -Path $policyPath -Name "DisableNotificationCenter" -Value 1 | Out-Null
    Set-QOTRegistryValue -Path $legacyPath -Name "DisableNotificationCenter" -Value 1 | Out-Null
}

function Invoke-QAdvancedDisplayPerformance {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"

    Set-QOTRegistryValue -Path $path -Name "VisualFXSetting" -Value 2 | Out-Null
}

Export-ModuleMember -Function `
    Invoke-QAdvancedAdobeNetworkBlock, `
    Invoke-QAdvancedBlockRazerInstalls, `
    Invoke-QAdvancedBraveDebloat, `
    Invoke-QAdvancedEdgeDebloat, `
    Invoke-QAdvancedDisableEdge, `
    Invoke-QAdvancedEdgeUninstallable, `
    Invoke-QAdvancedDisableBackgroundApps, `
    Invoke-QAdvancedDisableFullscreenOptimizations, `
    Invoke-QAdvancedDisableIPv6, `
    Invoke-QAdvancedDisableTeredo, `
    Invoke-QAdvancedDisableCopilot, `
    Invoke-QAdvancedDisableStorageSense, `
    Invoke-QAdvancedDisableNotificationTray, `
    Invoke-QAdvancedDisplayPerformance
