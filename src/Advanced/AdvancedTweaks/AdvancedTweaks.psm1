# AdvancedTweaks.psm1
# Advanced system and app tweaks (independent from Tweaks & Cleaning)

Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force

function New-QOTTaskResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("Success","Skipped","Failed")][string]$Status,
        [string]$Reason,
        [string]$Error
    )

    [pscustomobject]@{
        Name   = $Name
        Status = $Status
        Reason = $Reason
        Error  = $Error
    }
}

function New-QOTOperationResult {
    param(
        [Parameter(Mandatory)][ValidateSet("Success","Skipped","Failed")][string]$Status,
        [string]$Reason,
        [string]$Error
    )

    [pscustomobject]@{
        Status = $Status
        Reason = $Reason
        Error  = $Error
    }
}

function Resolve-QOTTaskResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object[]]$Operations
    )

    $failed = @($Operations | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($Operations | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($Operations | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
}

function Test-QOTIsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) { return $false }
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-QOTRegistryAdminRequired {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^(?i)HKLM:' ) { return $true }
    if ($Path -match '(?i)\\Policies\\') { return $true }
    return $false
}

function Set-QOTRegistryValueInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord"
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-QOTIsAdmin) -and (Test-QOTRegistryAdminRequired -Path $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    if (Test-Path -LiteralPath $Path) {
        try {
            $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $current) {
                $currentValue = $current.$Name
                if ($currentValue -eq $Value) {
                    return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
                }
            }
        }
        catch { }
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-QLog ("Advanced tweak: set {0}\\{1} = {2}" -f $Path, $Name, $Value)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to set {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Registry update failed" -Error $_.Exception.Message
    }
}

function Invoke-QOTRegistryTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable[]]$Operations
    )

    if (-not (Test-QOTIsAdmin)) {
        foreach ($operation in $Operations) {
            if (Test-QOTRegistryAdminRequired -Path $operation.Path) {
                return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Admin required"
            }
        }
    }

    $results = foreach ($operation in $Operations) {
        $type = $operation.Type
        if ($null -ne $type -and -not [string]::IsNullOrWhiteSpace($type)) {
            Set-QOTRegistryValueInternal -Path $operation.Path -Name $operation.Name -Value $operation.Value -Type $type
        } else {
            Set-QOTRegistryValueInternal -Path $operation.Path -Name $operation.Name -Value $operation.Value
        }
    }

    return Resolve-QOTTaskResult -Name $Name -Operations $results
}

function Set-QOTRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord"
    )

    Set-QOTRegistryValueInternal -Path $Path -Name $Name -Value $Value -Type $Type
}

function Add-QOTHostsEntries {
    param(
        [Parameter(Mandatory)][string[]]$Domains
    )

    $hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"

    try {
        if (-not (Test-Path -LiteralPath $hostsPath)) {
            Write-QLog "Hosts file not found; cannot add entries." "ERROR"
            return New-QOTOperationResult -Status "Failed" -Reason "Hosts file not found"
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
            return New-QOTOperationResult -Status "Success"
        }

        Write-QLog "Advanced tweak: hosts entries already present." "INFO"
        return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
    }
    catch {
        Write-QLog ("Advanced tweak failed to update hosts file: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Hosts update failed" -Error $_.Exception.Message
    }
}

function Add-QOTFirewallBlockRule {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$ProgramPath
    )

    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-QLog "Advanced tweak: New-NetFirewallRule not available." "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Firewall cmdlets unavailable"
    }

    if (-not (Test-Path -LiteralPath $ProgramPath)) {
        Write-QLog ("Advanced tweak: program not found for firewall block: {0}" -f $ProgramPath) "WARN"
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-QLog ("Advanced tweak: firewall rule already exists: {0}" -f $DisplayName)
            return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
        }

        New-NetFirewallRule -DisplayName $DisplayName -Direction Outbound -Program $ProgramPath -Action Block | Out-Null
        Write-QLog ("Advanced tweak: firewall rule created: {0}" -f $DisplayName)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to create firewall rule {0}: {1}" -f $DisplayName, $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Firewall rule failed" -Error $_.Exception.Message
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

    $results = @()
    $results += Add-QOTHostsEntries -Domains $domains

    $firewallTargets = @(
        "$env:ProgramFiles\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe",
        "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\ADS\Adobe Desktop Service.exe",
        "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\CEF\Adobe CEF Helper.exe"
    )

    foreach ($target in $firewallTargets) {
        $results += Add-QOTFirewallBlockRule -DisplayName ("QOT Block Adobe: {0}" -f [System.IO.Path]::GetFileName($target)) -ProgramPath $target
    }

    return Resolve-QOTTaskResult -Name "Adobe network block" -Operations $results
}

function Invoke-QAdvancedBlockRazerInstalls {
    $domains = @(
        "installer.razerzone.com",
        "drivers.razersupport.com",
        "rzr.to"
    )

    $result = Add-QOTHostsEntries -Domains $domains
    return Resolve-QOTTaskResult -Name "Block Razer installs" -Operations @($result)
}

function Invoke-QAdvancedBraveDebloat {
    $path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

    $ops = @(
        @{ Path = $path; Name = "BraveRewardsDisabled"; Value = 1 },
        @{ Path = $path; Name = "BraveWalletDisabled"; Value = 1 },
        @{ Path = $path; Name = "TorDisabled"; Value = 1 },
        @{ Path = $path; Name = "BackgroundModeEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Brave debloat" -Operations $ops
}

function Invoke-QAdvancedEdgeDebloat {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "HideFirstRunExperience"; Value = 1 },
        @{ Path = $path; Name = "StartupBoostEnabled"; Value = 0 },
        @{ Path = $path; Name = "BackgroundModeEnabled"; Value = 0 },
        @{ Path = $path; Name = "PromotionalTabsEnabled"; Value = 0 },
        @{ Path = $path; Name = "ShowRecommendationsEnabled"; Value = 0 },
        @{ Path = $path; Name = "EdgeShoppingAssistantEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Edge debloat" -Operations $ops
}

function Invoke-QAdvancedDisableEdge {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "AllowMicrosoftEdgeLaunchOnStartup"; Value = 0 },
        @{ Path = $path; Name = "AllowPrelaunch"; Value = 0 },
        @{ Path = $path; Name = "StartupBoostEnabled"; Value = 0 },
        @{ Path = $path; Name = "BackgroundModeEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Disable Edge" -Operations $ops
}

function Invoke-QAdvancedEdgeUninstallable {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "UninstallAllowed"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Edge uninstallable" -Operations $ops
}

function Invoke-QAdvancedDisableBackgroundApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"

    $ops = @(
        @{ Path = $path; Name = "GlobalUserDisabled"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable background apps" -Operations $ops
}

function Invoke-QAdvancedDisableFullscreenOptimizations {
    $path = "HKCU:\System\GameConfigStore"

    $ops = @(
        @{ Path = $path; Name = "GameDVR_FSEBehaviorMode"; Value = 2 },
        @{ Path = $path; Name = "GameDVR_HonorUserFSEBehaviorMode"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable fullscreen optimizations" -Operations $ops
}

function Invoke-QAdvancedDisableIPv6 {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"

    $ops = @(
        @{ Path = $path; Name = "DisabledComponents"; Value = 255 }
    )
    return Invoke-QOTRegistryTask -Name "Disable IPv6" -Operations $ops
}

function Invoke-QAdvancedDisableTeredo {
    try {
        & netsh interface teredo set state disabled | Out-Null
        Write-QLog "Advanced tweak: Teredo disabled."
        return New-QOTTaskResult -Name "Disable Teredo" -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to disable Teredo: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTTaskResult -Name "Disable Teredo" -Status "Failed" -Reason "Teredo update failed" -Error $_.Exception.Message
    }
}

function Invoke-QAdvancedDisableCopilot {
    $pathMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    $pathUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"

    $ops = @(
        @{ Path = $pathMachine; Name = "TurnOffWindowsCopilot"; Value = 1 },
        @{ Path = $pathUser; Name = "TurnOffWindowsCopilot"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable Copilot" -Operations $ops
}

function Invoke-QAdvancedDisableStorageSense {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"

    $ops = @(
        @{ Path = $path; Name = "01"; Value = 0 },
        @{ Path = $path; Name = "StorageSenseEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Disable Storage Sense" -Operations $ops
}

function Invoke-QAdvancedDisableNotificationTray {
    $policyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    $legacyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

    $ops = @(
        @{ Path = $policyPath; Name = "DisableNotificationCenter"; Value = 1 },
        @{ Path = $legacyPath; Name = "DisableNotificationCenter"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable notification tray" -Operations $ops
}

function Invoke-QAdvancedDisplayPerformance {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"

    $ops = @(
        @{ Path = $path; Name = "VisualFXSetting"; Value = 2 }
    )
    return Invoke-QOTRegistryTask -Name "Display performance" -Operations $ops
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
