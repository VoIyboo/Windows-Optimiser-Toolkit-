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
        if ($Root -is [System.Windows.FrameworkElement]) {
            $direct = $Root.FindName($Name)
            if ($direct) {
                return $direct
            }
        }

        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()
            if (-not $cur) { continue }

            $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
            if (-not $visited.Add($objId)) { continue }
            if ($cur -is [System.Windows.FrameworkElement]) {
                if ($cur.Name -eq $Name) {
                    return $cur
                }

                try {
                    $scoped = $cur.FindName($Name)
                    if ($scoped) {
                        return $scoped
                    }
                }
                catch { }
            }
            elseif ($cur -is [System.Windows.FrameworkContentElement]) {
                if ($cur.Name -eq $Name) {
                    return $cur
                }
            }

            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            }
            catch { }

            if ($cur -is [System.Windows.DependencyObject]) {
                $count = 0
                try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
                for ($i = 0; $i -lt $count; $i++) {
                    try {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                        if ($child) { $q.Enqueue($child) | Out-Null }
                    }
                    catch { }
                }
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
        $actionGroupName = "Tweaks & Cleaning"

        try {

            $uiCheckboxes = @()
            $missingUICheckboxes = @()
            foreach ($action in $actionsSnapshot) {
                $control = Get-QOTNamedElement -Root $Window -Name $action.Name
                if ($control -and $control -is [System.Windows.Controls.CheckBox]) {
                    $uiCheckboxes += [pscustomobject]@{
                        Name = $control.Name
                        Label = [string]$control.Content
                    }
                }
                else {
                    $missingUICheckboxes += $action
                }
            }

            $actionByName = @{}
            $duplicateActionNames = @()
            foreach ($action in $actionsSnapshot) {
                if (-not [string]::IsNullOrWhiteSpace($action.Name)) {
                    if ($actionByName.ContainsKey($action.Name)) {
                        $duplicateActionNames += $action.Name
                    } else {
                        $actionByName[$action.Name] = $action
                    }
                }
            }

            $duplicateUICheckboxes = @($uiCheckboxes | Group-Object Name | Where-Object { $_.Count -gt 1 })
            $missingFromActionList = @($uiCheckboxes | Where-Object { -not $actionByName.ContainsKey($_.Name) })
            $missingDefinitions = @()
            foreach ($action in $actionsSnapshot) {
                $definition = Get-QOTActionDefinition -ActionId $action.ActionId
                if (-not $definition) {
                    $missingDefinitions += $action
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($definition.ScriptPath) -or -not (Test-Path -LiteralPath $definition.ScriptPath)) {
                    $missingDefinitions += $action
                }
            }

            try { Write-QLog ("Tweaks & Cleaning checkboxes discovered in UI: {0}" -f $uiCheckboxes.Count) "INFO" } catch { }
            if ($uiCheckboxes.Count -eq 0) {
                $criticalMessage = "Tweaks & Cleaning checkboxes discovered in UI: 0. Startup halted to prevent silent action mismatches."
                try { Write-QLog $criticalMessage "CRITICAL" } catch {
                    try { Write-QLog $criticalMessage "ERROR" } catch { }
                }
                throw $criticalMessage
            }

            foreach ($cb in $uiCheckboxes) {
                try { Write-QLog ("Tweaks & Cleaning checkbox: {0} | {1}" -f $cb.Name, $cb.Label) "DEBUG" } catch { }
            }

            try { Write-QLog ("Tweaks & Cleaning actions mapped in UI module: {0}" -f $actionsSnapshot.Count) "INFO" } catch { }
            try {
                $catalogState = Get-QOTActionCatalogState
                Write-QLog ("ActionCatalog instance: {0} hash={1} count={2} (right before Tweaks UI mapping check)" -f $catalogState.TypeName, $catalogState.HashCode, $catalogState.Count) "INFO"
            } catch { }
            try { Write-QLog ("Total registered action definitions: {0}" -f (Get-QOTActionDefinitionCount)) "INFO" } catch { }

            if ($missingFromActionList.Count -gt 0) {
                foreach ($missing in $missingFromActionList) {
                    try { Write-QLog ("Tweaks & Cleaning checkbox has no mapped action definition: {0} | {1}" -f $missing.Name, $missing.Label) "WARN" } catch { }
                }
            }

            if ($missingDefinitions.Count -gt 0) {
                foreach ($missingDef in $missingDefinitions) {
                    try { Write-QLog ("Tweaks & Cleaning mapped action has no registered definition or script: {0} -> {1}" -f $missingDef.Name, $missingDef.ActionId) "WARN" } catch { }
                }
            }
            if ($missingUICheckboxes.Count -gt 0) {
                foreach ($missingUI in $missingUICheckboxes) {
                    try { Write-QLog ("Tweaks & Cleaning mapped checkbox missing in XAML: {0} -> {1}" -f $missingUI.Name, $missingUI.ActionId) "WARN" } catch { }
                }
            }
            if ($duplicateActionNames.Count -gt 0) {
                foreach ($duplicateName in ($duplicateActionNames | Select-Object -Unique)) {
                    try { Write-QLog ("Tweaks & Cleaning duplicate action Name detected: {0}" -f $duplicateName) "WARN" } catch { }
                }
            }

            if ($duplicateUICheckboxes.Count -gt 0) {
                foreach ($duplicateGroup in $duplicateUICheckboxes) {
                    try { Write-QLog ("Tweaks & Cleaning duplicate UI checkbox Name detected: {0}" -f $duplicateGroup.Name) "WARN" } catch { }
                }
            }

            if ($missingFromActionList.Count -eq 0 -and $missingDefinitions.Count -eq 0 -and $missingUICheckboxes.Count -eq 0 -and $uiCheckboxes.Count -eq $actionsSnapshot.Count -and $duplicateActionNames.Count -eq 0 -and $duplicateUICheckboxes.Count -eq 0) {
                try { Write-QLog "Tweaks & Cleaning checkbox/action mapping validated: no visual-only checkboxes detected." "INFO" } catch { }
            }
            if ($missingFromActionList.Count -gt 0 -or $missingDefinitions.Count -gt 0 -or $missingUICheckboxes.Count -gt 0) {
                $criticalMessage = "Tweaks & Cleaning checkbox/action mapping mismatch detected. Startup halted to prevent incorrect execution wiring."
                try { Write-QLog $criticalMessage "CRITICAL" } catch {
                    try { Write-QLog $criticalMessage "ERROR" } catch { }
                }
                throw $criticalMessage
            }
        }
        catch {
            try { Write-QLog ("Failed to validate Tweaks & Cleaning checkbox mappings: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            throw
        }
        
        Register-QOTActionGroup -Name $actionGroupName -GetItems ({
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
        throw
    }
}

Export-ModuleMember -Function Initialize-QOTTweaksAndCleaningUI
