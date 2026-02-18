# src\Core\Actions\ActionCatalog.psm1
# Registers ActionId-to-script mappings for the central action registry.

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue

function Initialize-QOTActionCatalog {
    $scriptsBasePath = Join-Path $PSScriptRoot "..\..\Scripts"

    try {
        Clear-QOTActionDefinitions
        Write-QOTActionCatalogState -Context "initialise catalog start"
    } catch { }

    function Register-QOTActionScript {
        param(
            [Parameter(Mandatory)][string]$ActionId,
            [Parameter(Mandatory)][string]$Label,
            [Parameter(Mandatory)][string]$RelativeScriptPath
        )
        $scriptPath = Join-Path $scriptsBasePath $RelativeScriptPath
        Register-QOTActionDefinition -ActionId $ActionId -Label $Label -ScriptPath $scriptPath
    }

    $actionDefinitions = @(
        @{ ActionId = "Invoke-QCleanTemp"; Label = "Clear temporary files"; Script = "Cleanup\\Invoke-QCleanTemp.ps1" },
        @{ ActionId = "Invoke-QCleanRecycleBin"; Label = "Empty Recycle Bin"; Script = "Cleanup\\Invoke-QCleanRecycleBin.ps1" },
        @{ ActionId = "Invoke-QCleanDOCache"; Label = "Clean Delivery Optimisation cache"; Script = "Cleanup\\Invoke-QCleanDOCache.ps1" },
        @{ ActionId = "Invoke-QCleanWindowsUpdateCache"; Label = "Clear Windows Update cache"; Script = "Cleanup\\Invoke-QCleanWindowsUpdateCache.ps1" },
        @{ ActionId = "Invoke-QCleanThumbnailCache"; Label = "Clean thumbnail cache"; Script = "Cleanup\\Invoke-QCleanThumbnailCache.ps1" },
        @{ ActionId = "Invoke-QCleanErrorLogs"; Label = "Clean old error logs and crash dumps"; Script = "Cleanup\\Invoke-QCleanErrorLogs.ps1" },
        @{ ActionId = "Invoke-QCleanSetupLeftovers"; Label = "Remove safe setup / upgrade leftovers"; Script = "Cleanup\\Invoke-QCleanSetupLeftovers.ps1" },
        @{ ActionId = "Invoke-QCleanStoreCache"; Label = "Clear Microsoft Store cache"; Script = "Cleanup\\Invoke-QCleanStoreCache.ps1" },
        @{ ActionId = "Invoke-QCleanEdgeCache"; Label = "Light clean of Microsoft Edge cache"; Script = "Cleanup\\Invoke-QCleanEdgeCache.ps1" },
        @{ ActionId = "Invoke-QCleanChromeCache"; Label = "Light clean of Chrome / Chromium cache"; Script = "Cleanup\\Invoke-QCleanChromeCache.ps1" },
        @{ ActionId = "Invoke-QCleanDirectXShaderCache"; Label = "Clear DirectX shader cache"; Script = "Cleanup\Invoke-QCleanDirectXShaderCache.ps1" },
        @{ ActionId = "Invoke-QCleanWERQueue"; Label = "Clear Windows Error Reporting queue"; Script = "Cleanup\Invoke-QCleanWERQueue.ps1" },
        @{ ActionId = "Invoke-QCleanClipboardHistory"; Label = "Clear clipboard history"; Script = "Cleanup\Invoke-QCleanClipboardHistory.ps1" },
        @{ ActionId = "Invoke-QCleanExplorerRecentItems"; Label = "Clear Explorer Recent items and Jump Lists"; Script = "Cleanup\Invoke-QCleanExplorerRecentItems.ps1" },
        @{ ActionId = "Invoke-QCleanWindowsSearchHistory"; Label = "Clear Windows Search history"; Script = "Cleanup\Invoke-QCleanWindowsSearchHistory.ps1" },
        @{ ActionId = "Invoke-QTweakStartMenuRecommendations"; Label = "Hide Start menu recommended items"; Script = "Tweaks\\Invoke-QTweakStartMenuRecommendations.ps1" },
        @{ ActionId = "Invoke-QTweakSuggestedApps"; Label = "Turn off suggested apps and promotions"; Script = "Tweaks\\Invoke-QTweakSuggestedApps.ps1" },
        @{ ActionId = "Invoke-QTweakTipsInStart"; Label = "Disable tips and suggestions in Start"; Script = "Tweaks\\Invoke-QTweakTipsInStart.ps1" },
        @{ ActionId = "Invoke-QTweakBingSearch"; Label = "Turn off Bing / web results in Start search"; Script = "Tweaks\\Invoke-QTweakBingSearch.ps1" },
        @{ ActionId = "Invoke-QTweakClassicContextMenu"; Label = "Use classic 'More options' right-click menu"; Script = "Tweaks\\Invoke-QTweakClassicContextMenu.ps1" },
        @{ ActionId = "Invoke-QTweakWidgets"; Label = "Turn off Widgets"; Script = "Tweaks\\Invoke-QTweakWidgets.ps1" },
        @{ ActionId = "Invoke-QTweakNewsAndInterests"; Label = "Turn off News / taskbar content"; Script = "Tweaks\\Invoke-QTweakNewsAndInterests.ps1" },
        @{ ActionId = "Invoke-QTweakMeetNow"; Label = "Hide legacy Meet Now button"; Script = "Tweaks\\Invoke-QTweakMeetNow.ps1" },
        @{ ActionId = "Invoke-QTweakAdvertisingId"; Label = "Turn off advertising ID"; Script = "Tweaks\\Invoke-QTweakAdvertisingId.ps1" },
        @{ ActionId = "Invoke-QTweakFeedbackHub"; Label = "Reduce feedback and survey prompts"; Script = "Tweaks\\Invoke-QTweakFeedbackHub.ps1" },
        @{ ActionId = "Invoke-QTweakOnlineTips"; Label = "Disable online tips and suggestions"; Script = "Tweaks\\Invoke-QTweakOnlineTips.ps1" },
        @{ ActionId = "Invoke-QTweakDisableLockScreenTips"; Label = "Disable lock screen tips, suggestions, and spotlight extras"; Script = "Tweaks\Invoke-QTweakDisableLockScreenTips.ps1" },
        @{ ActionId = "Invoke-QTweakDisableSettingsSuggestedContent"; Label = "Disable Suggested content in Settings"; Script = "Tweaks\Invoke-QTweakDisableSettingsSuggestedContent.ps1" },
        @{ ActionId = "Invoke-QTweakDisableTransparencyEffects"; Label = "Turn off transparency effects"; Script = "Tweaks\Invoke-QTweakDisableTransparencyEffects.ps1" },
        @{ ActionId = "Invoke-QTweakDisableStartupDelay"; Label = "Disable startup delay for startup apps"; Script = "Tweaks\Invoke-QTweakDisableStartupDelay.ps1" },
        @{ ActionId = "Invoke-QAdvancedAdobeNetworkBlock"; Label = "Adobe network block"; Script = "Network\\Invoke-QAdvancedAdobeNetworkBlock.ps1" },
        @{ ActionId = "Invoke-QAdvancedBlockRazerInstalls"; Label = "Block Razer software installs"; Script = "Tweaks\\Invoke-QAdvancedBlockRazerInstalls.ps1" },
        @{ ActionId = "Invoke-QAdvancedBraveDebloat"; Label = "Brave debloat"; Script = "Tweaks\\Invoke-QAdvancedBraveDebloat.ps1" },
        @{ ActionId = "Invoke-QAdvancedEdgeDebloat"; Label = "Edge debloat"; Script = "Tweaks\\Invoke-QAdvancedEdgeDebloat.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableEdge"; Label = "Disable Edge"; Script = "Tweaks\\Invoke-QAdvancedDisableEdge.ps1" },
        @{ ActionId = "Invoke-QAdvancedEdgeUninstallable"; Label = "Make Edge uninstallable via Settings"; Script = "Tweaks\\Invoke-QAdvancedEdgeUninstallable.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableBackgroundApps"; Label = "Disable background apps"; Script = "Tweaks\\Invoke-QAdvancedDisableBackgroundApps.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableFullscreenOptimizations"; Label = "Disable fullscreen optimizations"; Script = "Tweaks\\Invoke-QAdvancedDisableFullscreenOptimizations.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableIPv6"; Label = "Disable IPv6"; Script = "Network\\Invoke-QAdvancedDisableIPv6.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableTeredo"; Label = "Disable Teredo"; Script = "Network\\Invoke-QAdvancedDisableTeredo.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableCopilot"; Label = "Disable Microsoft Copilot"; Script = "Tweaks\\Invoke-QAdvancedDisableCopilot.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableStorageSense"; Label = "Disable Storage Sense"; Script = "Tweaks\\Invoke-QAdvancedDisableStorageSense.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisableNotificationTray"; Label = "Disable notification tray/calendar"; Script = "Tweaks\\Invoke-QAdvancedDisableNotificationTray.ps1" },
        @{ ActionId = "Invoke-QAdvancedDisplayPerformance"; Label = "Set display for performance"; Script = "Tweaks\\Invoke-QAdvancedDisplayPerformance.ps1" },
        @{ ActionId = "Invoke-QRemoveOldProfiles"; Label = "Remove old profiles"; Script = "Cleanup\\Invoke-QRemoveOldProfiles.ps1" },
        @{ ActionId = "Invoke-QAggressiveRestoreCleanup"; Label = "Aggressive restore/log cleanup"; Script = "Cleanup\\Invoke-QAggressiveRestoreCleanup.ps1" },
        @{ ActionId = "Invoke-QAdvancedDeepCache"; Label = "Deep cache/component store cleanup"; Script = "Cleanup\\Invoke-QAdvancedDeepCache.ps1" },
        @{ ActionId = "Invoke-QNetworkReset"; Label = "Network reset"; Script = "Network\\Invoke-QNetworkReset.ps1" },
        @{ ActionId = "Invoke-QRepairAdapter"; Label = "Repair network adapter"; Script = "Network\\Invoke-QRepairAdapter.ps1" },
        @{ ActionId = "Invoke-QServiceTune"; Label = "Service tuning"; Script = "Network\\Invoke-QServiceTune.ps1" }
    )

    foreach ($action in $actionDefinitions) {
        Register-QOTActionScript -ActionId $action.ActionId -Label $action.Label -RelativeScriptPath $action.Script
    }

    Register-QOTActionScript -ActionId "Apps.RunSelected" -Label "Run selected app actions" -RelativeScriptPath "Apps\\Apps.RunSelected.ps1"   
    try { Write-QOTActionCatalogState -Context "initialise catalog complete" } catch { }
    try { Write-QLog "Action catalog initialised." "DEBUG" } catch { }
}

Export-ModuleMember -Function Initialize-QOTActionCatalog
