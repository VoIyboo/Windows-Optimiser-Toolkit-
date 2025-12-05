# QOT.Actions.Tweaks.psm1
# Safe / debloat tweak actions

function Action-TweakStartMenuRecommendations { Write-Log "Disable Start menu recommendations (TODO)" }
function Action-TweakSuggestedApps            { Write-Log "Disable suggested apps / promos (TODO)" }
function Action-TweakWidgets                  { Write-Log "Disable Widgets (TODO)" }
function Action-TweakNewsInterests            { Write-Log "Disable News & Interests (TODO)" }
function Action-TweakBackgroundApps           { Write-Log "Limit background apps (TODO)" }
function Action-TweakAnimations               { Write-Log "Reduce / disable animations (TODO)" }
function Action-TweakOnlineTips               { Write-Log "Disable online tips (TODO)" }
function Action-TweakAdvertisingId            { Write-Log "Disable advertising ID (TODO)" }
function Action-TweakFeedbackHub              { Write-Log "Disable Feedback Hub prompts (TODO)" }
function Action-TweakTelemetrySafe            { Write-Log "Set telemetry to safe level (TODO)" }
function Action-TweakMeetNow                  { Write-Log "Turn off Meet Now (TODO)" }
function Action-TweakCortanaLeftovers         { Write-Log "Disable Cortana leftovers (TODO)" }
function Action-RemoveStockApps               { Write-Log "Remove unused stock apps (TODO)" }
function Action-TweakStartupSound             { Write-Log "Turn off startup sound (TODO)" }
function Action-TweakSnapAssist               { Write-Log "Turn off/customise Snap Assist (TODO)" }
function Action-TweakMouseAcceleration        { Write-Log "Turn off mouse acceleration (TODO)" }
function Action-ShowHiddenFiles               { Write-Log "Show hidden files and extensions (TODO)" }
function Action-VerboseLogon                  { Write-Log "Enable verbose logon messages (TODO)" }
function Action-DisableGameDVR                { Write-Log "Disable GameDVR (TODO)" }
function Action-DisableAppReinstall           { Write-Log "Disable auto reinstall of apps after updates (TODO)" }

Export-ModuleMember -Function `
    Action-TweakStartMenuRecommendations, `
    Action-TweakSuggestedApps, `
    Action-TweakWidgets, `
    Action-TweakNewsInterests, `
    Action-TweakBackgroundApps, `
    Action-TweakAnimations, `
    Action-TweakOnlineTips, `
    Action-TweakAdvertisingId, `
    Action-TweakFeedbackHub, `
    Action-TweakTelemetrySafe, `
    Action-TweakMeetNow, `
    Action-TweakCortanaLeftovers, `
    Action-RemoveStockApps, `
    Action-TweakStartupSound, `
    Action-TweakSnapAssist, `
    Action-TweakMouseAcceleration, `
    Action-ShowHiddenFiles, `
    Action-VerboseLogon, `
    Action-DisableGameDVR, `
    Action-DisableAppReinstall

