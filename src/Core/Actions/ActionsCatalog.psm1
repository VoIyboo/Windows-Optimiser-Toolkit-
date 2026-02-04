# src\Core\Actions\ActionCatalog.psm1
# Registers ActionId-to-script mappings for the central action registry.

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue

function Register-QOTActionDefinitionFromCommand {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$CommandName
    )

    Register-QOTActionDefinition -ActionId $ActionId -Label $Label -Execute ({
        param($window)
        $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw ("Command '{0}' not found for ActionId '{1}'." -f $CommandName, $ActionId)
        }
        & $cmd
    }).GetNewClosure()
}

function Initialize-QOTActionCatalog {
    $basePath = Join-Path $PSScriptRoot "..\.."

    Import-Module (Join-Path $basePath "TweaksAndCleaning\CleaningAndMain\Cleaning.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Advanced\AdvancedTweaks\AdvancedTweaks.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Advanced\AdvancedCleaning\AdvancedCleaning.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $basePath "Advanced\NetworkAndServices\NetworkAndServices.psm1") -Force -ErrorAction SilentlyContinue

    $actionDefinitions = @(
        @{ ActionId = "Invoke-QCleanTemp"; Label = "Clear temporary files" },
        @{ ActionId = "Invoke-QCleanRecycleBin"; Label = "Empty Recycle Bin" },
        @{ ActionId = "Invoke-QCleanDOCache"; Label = "Clean Delivery Optimisation cache" },
        @{ ActionId = "Invoke-QCleanWindowsUpdateCache"; Label = "Clear Windows Update cache" },
        @{ ActionId = "Invoke-QCleanThumbnailCache"; Label = "Clean thumbnail cache" },
        @{ ActionId = "Invoke-QCleanErrorLogs"; Label = "Clean old error logs and crash dumps" },
        @{ ActionId = "Invoke-QCleanSetupLeftovers"; Label = "Remove safe setup / upgrade leftovers" },
        @{ ActionId = "Invoke-QCleanStoreCache"; Label = "Clear Microsoft Store cache" },
        @{ ActionId = "Invoke-QCleanEdgeCache"; Label = "Light clean of Microsoft Edge cache" },
        @{ ActionId = "Invoke-QCleanChromeCache"; Label = "Light clean of Chrome / Chromium cache" },
        @{ ActionId = "Invoke-QTweakStartMenuRecommendations"; Label = "Hide Start menu recommended items" },
        @{ ActionId = "Invoke-QTweakSuggestedApps"; Label = "Turn off suggested apps and promotions" },
        @{ ActionId = "Invoke-QTweakTipsInStart"; Label = "Disable tips and suggestions in Start" },
        @{ ActionId = "Invoke-QTweakBingSearch"; Label = "Turn off Bing / web results in Start search" },
        @{ ActionId = "Invoke-QTweakClassicContextMenu"; Label = "Use classic 'More options' right-click menu" },
        @{ ActionId = "Invoke-QTweakWidgets"; Label = "Turn off Widgets" },
        @{ ActionId = "Invoke-QTweakNewsAndInterests"; Label = "Turn off News / taskbar content" },
        @{ ActionId = "Invoke-QTweakMeetNow"; Label = "Hide legacy Meet Now button" },
        @{ ActionId = "Invoke-QTweakAdvertisingId"; Label = "Turn off advertising ID" },
        @{ ActionId = "Invoke-QTweakFeedbackHub"; Label = "Reduce feedback and survey prompts" },
        @{ ActionId = "Invoke-QTweakOnlineTips"; Label = "Disable online tips and suggestions" },
        @{ ActionId = "Invoke-QAdvancedAdobeNetworkBlock"; Label = "Adobe network block" },
        @{ ActionId = "Invoke-QAdvancedBlockRazerInstalls"; Label = "Block Razer software installs" },
        @{ ActionId = "Invoke-QAdvancedBraveDebloat"; Label = "Brave debloat" },
        @{ ActionId = "Invoke-QAdvancedEdgeDebloat"; Label = "Edge debloat" },
        @{ ActionId = "Invoke-QAdvancedDisableEdge"; Label = "Disable Edge" },
        @{ ActionId = "Invoke-QAdvancedEdgeUninstallable"; Label = "Make Edge uninstallable via Settings" },
        @{ ActionId = "Invoke-QAdvancedDisableBackgroundApps"; Label = "Disable background apps" },
        @{ ActionId = "Invoke-QAdvancedDisableFullscreenOptimizations"; Label = "Disable fullscreen optimizations" },
        @{ ActionId = "Invoke-QAdvancedDisableIPv6"; Label = "Disable IPv6" },
        @{ ActionId = "Invoke-QAdvancedDisableTeredo"; Label = "Disable Teredo" },
        @{ ActionId = "Invoke-QAdvancedDisableCopilot"; Label = "Disable Microsoft Copilot" },
        @{ ActionId = "Invoke-QAdvancedDisableStorageSense"; Label = "Disable Storage Sense" },
        @{ ActionId = "Invoke-QAdvancedDisableNotificationTray"; Label = "Disable notification tray/calendar" },
        @{ ActionId = "Invoke-QAdvancedDisplayPerformance"; Label = "Set display for performance" },
        @{ ActionId = "Invoke-QRemoveOldProfiles"; Label = "Remove old profiles" },
        @{ ActionId = "Invoke-QAggressiveRestoreCleanup"; Label = "Aggressive restore/log cleanup" },
        @{ ActionId = "Invoke-QAdvancedDeepCache"; Label = "Deep cache/component store cleanup" },
        @{ ActionId = "Invoke-QNetworkReset"; Label = "Network reset" },
        @{ ActionId = "Invoke-QRepairAdapter"; Label = "Repair network adapter" },
        @{ ActionId = "Invoke-QServiceTune"; Label = "Service tuning" }
    )

    foreach ($action in $actionDefinitions) {
        Register-QOTActionDefinitionFromCommand -ActionId $action.ActionId -Label $action.Label -CommandName $action.ActionId
    }

    Register-QOTActionDefinition -ActionId "Apps.RunSelected" -Label "Run selected app actions" -Execute ({
        param($window)
        if (-not $window) {
            throw "Window context missing for Apps.RunSelected."
        }

        $appsGrid = $window.FindName("AppsGrid")
        $installGrid = $window.FindName("InstallGrid")
        $statusLabel = $window.FindName("StatusLabel")

        if (-not $appsGrid -or -not $installGrid) {
            throw "Apps grids not available for Apps.RunSelected."
        }

        $cmd = Get-Command Invoke-QOTRunSelectedAppsActions -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Invoke-QOTRunSelectedAppsActions not available."
        }

        & $cmd -Window $window -AppsGrid $appsGrid -InstallGrid $installGrid -StatusLabel $statusLabel
    })

    try { Write-QLog "Action catalog initialised." "DEBUG" } catch { }
}

Export-ModuleMember -Function Initialize-QOTActionCatalog
