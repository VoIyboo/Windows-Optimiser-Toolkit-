# TweaksAndPrivacy.psm1
# Quinn Optimiser Toolkit – Tweaks & Privacy module
# Handles UI / privacy / telemetry / UX tweaks.

# ------------------------------
# Import core logging
# ------------------------------
Import-Module "$PSScriptRoot\..\..\Core\Config\Config.psm1"   -Force
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

function Set-QOTRegistryValueInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord",
        [switch]$DefaultValue
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-QOTIsAdmin) -and (Test-QOTRegistryAdminRequired -Path $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }
    try {
        if (Test-Path -LiteralPath $Path) {
            try {
                $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $current) {
                    $currentValue = $current.$Name
                    if ($currentValue -eq $Value) {
                        return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
                    }
                }
            } catch { }
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        if ($DefaultValue) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force | Out-Null
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
        Write-QLog ("Tweaks: set {0}\\{1} = {2}" -f $Path, $Name, $Value)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Tweaks: failed to set {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
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
        $path = $operation.Path
        $value = $operation.Value
        $type = $operation.Type
        if ($operation.DefaultValue) {
            Set-QOTRegistryValueInternal -Path $path -Name "(default)" -Value $value -DefaultValue
        } else {
            if ($null -ne $type -and -not [string]::IsNullOrWhiteSpace($type)) {
                Set-QOTRegistryValueInternal -Path $path -Name $operation.Name -Value $value -Type $type
            } else {
                Set-QOTRegistryValueInternal -Path $path -Name $operation.Name -Value $value
            }
        }
    }
    $failed = @($results | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($results | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($results | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
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

function Set-QOTRegistryDefaultValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    Set-QOTRegistryValueInternal -Path $Path -Name "(default)" -Value $Value -DefaultValue
}
# ------------------------------
# Start menu / recommendations
# ------------------------------

function Write-QOTTaskOutcome {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][object]$Result
    )

    $status = "SKIPPED"
    switch ([string]$Result.Status) {
        "Success" { $status = "SUCCESS" }
        "Failed" { $status = "FAILED" }
        default { $status = "SKIPPED" }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Result.Reason)) {
        Write-QLog ("Task result: {0} => {1} ({2})" -f $TaskName, $status, [string]$Result.Reason)
    } else {
        Write-QLog ("Task result: {0} => {1}" -f $TaskName, $status)
    }
}

function Invoke-QOTLoggedRegistryTask {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][hashtable[]]$Operations
    )

    Write-QLog ("Now doing task: {0}" -f $TaskName)
    $result = Invoke-QOTRegistryTask -Name $TaskName -Operations $Operations
    if ($result.Status -eq "Skipped" -and $result.Reason -eq "Admin required") {
        $result = New-QOTTaskResult -Name $TaskName -Status "Failed" -Reason "requires admin"
    }
    Write-QOTTaskOutcome -TaskName $TaskName -Result $result
    return $result
}

function Invoke-QTweakStartMenuRecommendations {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 }
    )
    Write-QLog "Tweaks: Start menu recommendations disabled."
    return Invoke-QOTRegistryTask -Name "Start menu recommendations" -Operations $ops
}

function Invoke-QTweakSuggestedApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338388Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353698Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 0 },
        @{ Path = $path; Name = "SilentInstalledAppsEnabled"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 }
    )
    Write-QLog "Tweaks: Suggested apps and promotions disabled."
    return Invoke-QOTRegistryTask -Name "Suggested apps and promotions" -Operations $ops
}

function Invoke-QTweakTipsInStart {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 0 },
        @{ Path = $path; Name = "SystemPaneSuggestionsEnabled"; Value = 0 }
    )
    Write-QLog "Tweaks: Tips and suggestions in Start disabled."
    return Invoke-QOTRegistryTask -Name "Tips in Start" -Operations $ops
}

function Invoke-QTweakBingSearch {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1 },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Value = 1 }
    )
    Write-QLog "Tweaks: Bing/web results in Start search disabled."
    return Invoke-QOTRegistryTask -Name "Bing search" -Operations $ops
}

function Invoke-QTweakClassicContextMenu {
    $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    $ops = @(
        @{ Path = $path; Value = ""; DefaultValue = $true }
    )
    Write-QLog "Tweaks: Classic context menu enabled (restart Explorer for effect)."
    return Invoke-QOTRegistryTask -Name "Classic context menu" -Operations $ops
}

# ------------------------------
# Widgets / News & Interests
# ------------------------------
function Invoke-QTweakWidgets {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    $ops = @(
        @{ Path = $path; Name = "AllowWidgets"; Value = 0 },
        @{ Path = $path; Name = "AllowNewsAndInterests"; Value = 0 }
    )
    Write-QLog "Tweaks: Widgets disabled."
    return Invoke-QOTRegistryTask -Name "Widgets" -Operations $ops
}

function Invoke-QTweakNewsAndInterests {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Name = "EnableFeeds"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name = "ShellFeedsTaskbarViewMode"; Value = 2 }
    )
    Write-QLog "Tweaks: News/taskbar content disabled."
    return Invoke-QOTRegistryTask -Name "News and interests" -Operations $ops
}

# ------------------------------
# Background apps / animations
# ------------------------------
function Invoke-QTweakBackgroundApps {
    Write-QLog "Tweaks: Limit or disable background apps (placeholder)"
}

function Invoke-QTweakAnimations {
    Write-QLog "Tweaks: Reduce / disable animations (placeholder)"
}

# ------------------------------
# Tips / advertising / feedback
# ------------------------------
function Invoke-QTweakOnlineTips {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353696Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353698Enabled"; Value = 0 }
    )
    Write-QLog "Tweaks: Online tips and suggestions disabled."
    return Invoke-QOTRegistryTask -Name "Online tips" -Operations $ops
}

function Invoke-QTweakAdvertisingId {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name = "DisabledByGroupPolicy"; Value = 1 }
    )
    Write-QLog "Tweaks: Advertising ID disabled."
    return Invoke-QOTRegistryTask -Name "Advertising ID" -Operations $ops
}

function Invoke-QTweakFeedbackHub {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "NumberOfSIUFInPeriod"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "PeriodInNanoSeconds"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 1 }
    )
    Write-QLog "Tweaks: Feedback and survey prompts reduced."
    return Invoke-QOTRegistryTask -Name "Feedback hub" -Operations $ops
}

function Invoke-QTweakTelemetrySafe {
    Write-QLog "Tweaks: Set telemetry to safe/minimal level (placeholder)"
}

# ------------------------------
# Meet Now / Cortana / stock apps
# ------------------------------
function Invoke-QTweakMeetNow {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideSCAMeetNow"; Value = 1 }
    )
    Write-QLog "Tweaks: Meet Now hidden."
    return Invoke-QOTRegistryTask -Name "Meet now" -Operations $ops
}

function Invoke-QTweakCortanaLeftovers {
    Write-QLog "Tweaks: Turn off Cortana leftovers (placeholder)"
}

function Invoke-QRemoveStockApps {
    Write-QLog "Tweaks: Remove unused stock apps (placeholder)"
}

# ------------------------------
# Startup / Snap / mouse / explorer
# ------------------------------
function Invoke-QTweakStartupSound {
    Write-QLog "Tweaks: Turn off startup sound (placeholder)"
}

function Invoke-QTweakSnapAssist {
    Write-QLog "Tweaks: Adjust Snap Assist (placeholder)"
}

function Invoke-QTweakMouseAcceleration {
    Write-QLog "Tweaks: Disable mouse acceleration (placeholder)"
}

function Invoke-QShowHiddenFiles {
    Write-QLog "Tweaks: Show hidden files and file extensions (placeholder)"
}

function Invoke-QEnableVerboseLogon {
    Write-QLog "Tweaks: Enable verbose logon messages (placeholder)"
}

function Invoke-QDisableGameDVR {
    Write-QLog "Tweaks: Disable GameDVR (placeholder)"
}

function Invoke-QDisableAppReinstall {
    Write-QLog "Tweaks: Disable auto reinstall of apps (placeholder)"
}

function Invoke-QTweakDisableLockScreenTips {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338387Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338388Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 0 },
        @{ Path = $path; Name = "RotatingLockScreenEnabled"; Value = 0 },
        @{ Path = $path; Name = "RotatingLockScreenOverlayEnabled"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable lock screen tips, suggestions, and spotlight extras" -Operations $ops
}

function Invoke-QTweakDisableSettingsSuggestedContent {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable Suggested content in Settings" -Operations $ops
}

function Invoke-QTweakDisableTransparencyEffects {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $ops = @(
        @{ Path = $path; Name = "EnableTransparency"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Turn off transparency effects" -Operations $ops
}

function Invoke-QTweakDisableStartupDelay {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
    $ops = @(
        @{ Path = $path; Name = "StartupDelayInMSec"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable startup delay for startup apps" -Operations $ops
}


# ------------------------------
# Exported functions
# ------------------------------
Export-ModuleMember -Function `
    Invoke-QTweakStartMenuRecommendations, `
    Invoke-QTweakSuggestedApps, `
    Invoke-QTweakTipsInStart, `
    Invoke-QTweakBingSearch, `
    Invoke-QTweakClassicContextMenu, `
    Invoke-QTweakWidgets, `
    Invoke-QTweakNewsAndInterests, `
    Invoke-QTweakBackgroundApps, `
    Invoke-QTweakAnimations, `
    Invoke-QTweakOnlineTips, `
    Invoke-QTweakAdvertisingId, `
    Invoke-QTweakFeedbackHub, `
    Invoke-QTweakTelemetrySafe, `
    Invoke-QTweakMeetNow, `
    Invoke-QTweakCortanaLeftovers, `
    Invoke-QRemoveStockApps, `
    Invoke-QTweakStartupSound, `
    Invoke-QTweakSnapAssist, `
    Invoke-QTweakMouseAcceleration, `
    Invoke-QShowHiddenFiles, `
    Invoke-QEnableVerboseLogon, `
    Invoke-QDisableGameDVR, `
    Invoke-QDisableAppReinstall, `
    Invoke-QTweakDisableLockScreenTips, `
    Invoke-QTweakDisableSettingsSuggestedContent, `
    Invoke-QTweakDisableTransparencyEffects, `
    Invoke-QTweakDisableStartupDelay
