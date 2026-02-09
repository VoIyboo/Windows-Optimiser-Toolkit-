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
        [int]$Succeeded = 0,
        [int]$Failed = 0
    )

    $status = "Failed"
    if ($Succeeded -gt 0 -and $Failed -eq 0) {
        $status = "Success"
    }
    elseif ($Succeeded -gt 0 -and $Failed -gt 0) {
        $status = "Partial"
    }

    [pscustomobject]@{
        Name               = $Name
        Status             = $status
        SuccessfulOpsCount = $Succeeded
        FailedOpsCount     = $Failed
        TotalOpsCount      = ($Succeeded + $Failed)
    }
}

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
        Write-QLog ("Tweaks: set {0}\\{1} = {2}" -f $Path, $Name, $Value)
        return $true
    }
    catch {
        Write-QLog ("Tweaks: failed to set {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
        return $false
    }
}

function Set-QOTRegistryDefaultValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        Set-ItemProperty -Path $Path -Name "(default)" -Value $Value -Force | Out-Null
        Write-QLog ("Tweaks: set {0}\\(Default) = {1}" -f $Path, $Value)
        return $true
    }
    catch {
        Write-QLog ("Tweaks: failed to set default for {0}: {1}" -f $Path, $_.Exception.Message) "ERROR"
        return $false
    }
}

# ------------------------------
# Start menu / recommendations
# ------------------------------
function Invoke-QTweakStartMenuRecommendations {
    $ops = @(
        Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 1,
        Set-QOTRegistryValue -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 1
    )
    Write-QLog "Tweaks: Start menu recommendations disabled."
    return New-QOTTaskResult -Name "Start menu recommendations" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakSuggestedApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-338388Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-338389Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-353698Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-353694Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SilentInstalledAppsEnabled" -Value 0,
        Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
    )
    Write-QLog "Tweaks: Suggested apps and promotions disabled."
    return New-QOTTaskResult -Name "Suggested apps and promotions" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakTipsInStart {
    $ops = @(
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-338389Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-338393Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SystemPaneSuggestionsEnabled" -Value 0
    )
    Write-QLog "Tweaks: Tips and suggestions in Start disabled."
    return New-QOTTaskResult -Name "Tips in Start" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakBingSearch {
    $ops = @(
        Set-QOTRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0,
        Set-QOTRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0,
        Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1,
        Set-QOTRegistryValue -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
    )
    Write-QLog "Tweaks: Bing/web results in Start search disabled."
    return New-QOTTaskResult -Name "Bing search" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakClassicContextMenu {
    $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    $ok = Set-QOTRegistryDefaultValue -Path $path -Value ""
    Write-QLog "Tweaks: Classic context menu enabled (restart Explorer for effect)."
    return New-QOTTaskResult -Name "Classic context menu" -Succeeded ([int][bool]$ok) -Failed ([int](-not $ok))
}

# ------------------------------
# Widgets / News & Interests
# ------------------------------
function Invoke-QTweakWidgets {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    $ops = @(
        Set-QOTRegistryValue -Path $path -Name "AllowWidgets" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "AllowNewsAndInterests" -Value 0
    )
    Write-QLog "Tweaks: Widgets disabled."
    return New-QOTTaskResult -Name "Widgets" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakNewsAndInterests {
    $ops = @(
        Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0,
        Set-QOTRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2
    )
    Write-QLog "Tweaks: News/taskbar content disabled."
    return New-QOTTaskResult -Name "News and interests" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
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
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-338393Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-353694Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-353696Enabled" -Value 0,
        Set-QOTRegistryValue -Path $path -Name "SubscribedContent-353698Enabled" -Value 0
    )
    Write-QLog "Tweaks: Online tips and suggestions disabled."
    return New-QOTTaskResult -Name "Online tips" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakAdvertisingId {
    $ops = @(
        Set-QOTRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0,
        Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1
    )
    Write-QLog "Tweaks: Advertising ID disabled."
    return New-QOTTaskResult -Name "Advertising ID" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakFeedbackHub {
    $ops = @(
        Set-QOTRegistryValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0,
        Set-QOTRegistryValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Value 0,
        Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1
    )
    Write-QLog "Tweaks: Feedback and survey prompts reduced."
    return New-QOTTaskResult -Name "Feedback hub" -Succeeded (($ops | Where-Object { $_ }).Count) -Failed (($ops | Where-Object { -not $_ }).Count)
}

function Invoke-QTweakTelemetrySafe {
    Write-QLog "Tweaks: Set telemetry to safe/minimal level (placeholder)"
}

# ------------------------------
# Meet Now / Cortana / stock apps
# ------------------------------
function Invoke-QTweakMeetNow {
    $ok = Set-QOTRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideSCAMeetNow" -Value 1
    Write-QLog "Tweaks: Meet Now hidden."
    return New-QOTTaskResult -Name "Meet now" -Succeeded ([int][bool]$ok) -Failed ([int](-not $ok))
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
    Invoke-QDisableAppReinstall
