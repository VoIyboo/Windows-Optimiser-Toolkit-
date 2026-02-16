# src\TweaksAndCleaning\TweaksAndCleaning.UI.psm1
# UI wiring for the Tweaks & Cleaning tab

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Core\Config\Config.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Actions\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue

Import-Module "$PSScriptRoot\Cleaning.psm1"                          -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force -ErrorAction Stop

function Get-QOTNamedElement {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    try {
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()
            if ($cur -is [System.Windows.FrameworkElement]) {
                if ($cur.Name -eq $Name) {
                    return $cur
                }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    }
    catch { }

    return $null
}



function Initialize-QOTTweaksAndCleaningUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    try {
        $actions = @(
            @{ Name = "CbCleanTempFiles";       Label = "Clear temporary files";                 ActionId = "Invoke-QCleanTemp" },
            @{ Name = "CbEmptyRecycleBin";      Label = "Empty Recycle Bin";                      ActionId = "Invoke-QCleanRecycleBin" },
            @{ Name = "CbCleanDoCache";         Label = "Clean Delivery Optimisation cache";      ActionId = "Invoke-QCleanDOCache" },
            @{ Name = "CbCleanWuCache";         Label = "Clear Windows Update cache";             ActionId = "Invoke-QCleanWindowsUpdateCache" },
            @{ Name = "CbCleanThumbCache";      Label = "Clean thumbnail cache";                  ActionId = "Invoke-QCleanThumbnailCache" },
            @{ Name = "CbCleanErrorLogs";       Label = "Clean old error logs and crash dumps";   ActionId = "Invoke-QCleanErrorLogs" },
            @{ Name = "CbCleanSetupLeftovers";  Label = "Remove safe setup / upgrade leftovers";  ActionId = "Invoke-QCleanSetupLeftovers" },
            @{ Name = "CbClearStoreCache";      Label = "Clear Microsoft Store cache";            ActionId = "Invoke-QCleanStoreCache" },
            @{ Name = "CbEdgeLightCleanup";     Label = "Light clean of Microsoft Edge cache";    ActionId = "Invoke-QCleanEdgeCache" },
            @{ Name = "CbChromeLightCleanup";   Label = "Light clean of Chrome / Chromium cache"; ActionId = "Invoke-QCleanChromeCache" },
            @{ Name = "CbCleanDirectXShaderCache"; Label = "Clear DirectX shader cache"; ActionId = "Invoke-QCleanDirectXShaderCache" },
            @{ Name = "CbCleanWERQueue"; Label = "Clear Windows Error Reporting queue"; ActionId = "Invoke-QCleanWERQueue" },
            @{ Name = "CbClearClipboardHistory"; Label = "Clear clipboard history"; ActionId = "Invoke-QCleanClipboardHistory" },
            @{ Name = "CbCleanExplorerRecentItems"; Label = "Clear Explorer Recent items and Jump Lists"; ActionId = "Invoke-QCleanExplorerRecentItems" },
            @{ Name = "CbCleanWindowsSearchHistory"; Label = "Clear Windows Search history"; ActionId = "Invoke-QCleanWindowsSearchHistory" },
            @{ Name = "CbDisableStartRecommended"; Label = "Hide Start menu recommended items";   ActionId = "Invoke-QTweakStartMenuRecommendations" },
            @{ Name = "CbDisableSuggestedApps";    Label = "Turn off suggested apps and promotions"; ActionId = "Invoke-QTweakSuggestedApps" },
            @{ Name = "CbDisableTipsStart";        Label = "Disable tips and suggestions in Start"; ActionId = "Invoke-QTweakTipsInStart" },
            @{ Name = "CbDisableBingSearch";       Label = "Turn off Bing / web results in Start search"; ActionId = "Invoke-QTweakBingSearch" },
            @{ Name = "CbClassicMoreOptions";      Label = "Use classic 'More options' right-click menu"; ActionId = "Invoke-QTweakClassicContextMenu" },
            @{ Name = "CbDisableWidgets";          Label = "Turn off Widgets";                    ActionId = "Invoke-QTweakWidgets" },
            @{ Name = "CbDisableTaskbarNews";      Label = "Turn off News / taskbar content";      ActionId = "Invoke-QTweakNewsAndInterests" },
            @{ Name = "CbDisableMeetNow";          Label = "Hide legacy Meet Now button";          ActionId = "Invoke-QTweakMeetNow" },
            @{ Name = "CbDisableAdvertisingId";    Label = "Turn off advertising ID";              ActionId = "Invoke-QTweakAdvertisingId" },
            @{ Name = "CbLimitFeedbackPrompts";    Label = "Reduce feedback and survey prompts";   ActionId = "Invoke-QTweakFeedbackHub" },
            @{ Name = "CbDisableOnlineTips";       Label = "Disable online tips and suggestions";  ActionId = "Invoke-QTweakOnlineTips" },
            @{ Name = "CbDisableLockScreenTips"; Label = "Disable lock screen tips, suggestions, and spotlight extras"; ActionId = "Invoke-QTweakDisableLockScreenTips" },
            @{ Name = "CbDisableSettingsSuggestedContent"; Label = "Disable Suggested content in Settings"; ActionId = "Invoke-QTweakDisableSettingsSuggestedContent" },
            @{ Name = "CbDisableTransparencyEffects"; Label = "Turn off transparency effects"; ActionId = "Invoke-QTweakDisableTransparencyEffects" },
            @{ Name = "CbDisableStartupDelay"; Label = "Disable startup delay for startup apps"; ActionId = "Invoke-QTweakDisableStartupDelay" }
        )
        
        $actionsSnapshot = $actions

        Register-QOTActionGroup -Name "Tweaks & Cleaning" -GetItems ({
            param($Window)

            $items = @()
            foreach ($action in $actionsSnapshot) {
                $actionName = $action.Name
                $actionLabel = $action.Label
                $actionId = $action.ActionId

                $items += [pscustomobject]@{
                    ActionId = $actionId
                    Label = $actionLabel
                    IsSelected = ({
                        param($window)
                        $control = Get-QOTNamedElement -Root $window -Name $actionName
                        $control -and $control.IsChecked -eq $true
                    }).GetNewClosure()
                }
            }
            return $items
        }).GetNewClosure()

        try { Write-QLog "Tweaks & Cleaning UI initialised (action registry)." "DEBUG" } catch { }
    }
    catch {
        try { Write-QLog ("Tweaks/Cleaning UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Initialize-QOTTweaksAndCleaningUI
