# TweaksAndPrivacy.psm1
# Quinn Optimiser Toolkit – Tweaks & Privacy module
# Handles UI / privacy / telemetry / UX tweaks.

# ------------------------------
# Import core logging
# ------------------------------
Import-Module "$PSScriptRoot\..\..\..\Core\Config\Config.psm1"    -Force
Import-Module "$PSScriptRoot\..\..\..\Core\Logging\Logging.psm1"  -Force

# ------------------------------
# Start menu / recommendations
# ------------------------------
function Invoke-QTweakStartMenuRecommendations {
    Write-QLog "Tweaks: Disable Start menu recommendations (placeholder)"
}

function Invoke-QTweakSuggestedApps {
    Write-QLog "Tweaks: Disable suggested apps / promos (placeholder)"
}

# ------------------------------
# Widgets / News & Interests
# ------------------------------
function Invoke-QTweakWidgets {
    Write-QLog "Tweaks: Disable Widgets (placeholder)"
}

function Invoke-QTweakNewsAndInterests {
    Write-QLog "Tweaks: Disable News & Interests (placeholder)"
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
    Write-QLog "Tweaks: Turn off online tips & suggestions (placeholder)"
}

function Invoke-QTweakAdvertisingId {
    Write-QLog "Tweaks: Disable advertising ID (placeholder)"
}

function Invoke-QTweakFeedbackHub {
    Write-QLog "Tweaks: Disable Feedback Hub prompts (placeholder)"
}

function Invoke-QTweakTelemetrySafe {
    Write-QLog "Tweaks: Set telemetry to safe/minimal level (placeholder)"
}

# ------------------------------
# Meet Now / Cortana / stock apps
# ------------------------------
function Invoke-QTweakMeetNow {
    Write-QLog "Tweaks: Turn off Meet Now (placeholder)"
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
