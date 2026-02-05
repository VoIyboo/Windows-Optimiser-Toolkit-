# src\UI\HelpWindow.UI.psm1
# Help window UI for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOTHelp_AssembliesLoaded = $false

function Initialize-QOTHelpUIAssemblies {
    if ($script:QOTHelp_AssembliesLoaded) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    $script:QOTHelp_AssembliesLoaded = $true
}

function Convert-HelpWindowToHostableRoot {
    param([Parameter(Mandatory)][xml]$Doc)

    $win = $Doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "HelpWindow.xaml root must be <Window>."
    }

    $ns   = $win.NamespaceURI
    $grid = $Doc.CreateElement("Grid", $ns)

    $removeAttrs = @(
        "Title","Height","Width","Topmost","WindowStartupLocation",
        "ResizeMode","SizeToContent","ShowInTaskbar","WindowStyle","AllowsTransparency"
    )

    foreach ($a in @($win.Attributes)) {
        if ($removeAttrs -contains $a.Name) { continue }
        $null = $grid.Attributes.Append($a.Clone())
    }

    foreach ($child in @($win.ChildNodes)) {
        if ($child.NodeType -ne "Element") { continue }

        if ($child.LocalName -eq "Window.Resources") {
            $newRes = $Doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        } else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $Doc.RemoveChild($win)
    $null = $Doc.AppendChild($grid)

    return $Doc
}

function Get-QOTHelpSections {
    return @(
        [pscustomobject]@{
            Title = "How Quinn Optimiser Toolkit works"
            Body  = "Quinn Optimiser Toolkit groups maintenance tasks into tabs such as Tweaks & Cleaning, Apps, and Advanced. Each section presents selectable tasks so you can build a custom run list for the current machine."
        }
        [pscustomobject]@{
            Title = "Checkboxes map directly to actions"
            Body  = "Each checkbox represents a specific action in the toolkit. Selecting a checkbox queues that action, and clearing it removes the action from the run list. You can mix actions across tabs - every checked item is included."
        }
        [pscustomobject]@{
            Title = 'What "Run selected actions" does'
            Body  = "The Run selected actions button executes every checked item in sequence. It only runs what is selected at the time you click the button and leaves unchecked actions untouched."
        }
        [pscustomobject]@{
            Title = "Important safety notes"
            Body  = "* Review selections before running any actions.`n* Close important apps to avoid file locks or conflicts.`n* Some actions change system settings - use a maintenance window when possible.`n* If you are unsure about an action, leave it unchecked and review it first."
        }
    )
}

function New-QOTHelpView {
    Initialize-QOTHelpUIAssemblies

    $xamlPath = Join-Path $PSScriptRoot "HelpWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "HelpWindow.xaml not found at $xamlPath"
    }
    
    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $doc = Convert-HelpWindowToHostableRoot -Doc $doc
    
    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $root) { throw "Failed to load HelpWindow.xaml" }

    $sectionsControl = $root.FindName("HelpSections")
    if ($sectionsControl) {
        $sectionsControl.ItemsSource = (Get-QOTHelpSections)
    }

    return $root
}

Export-ModuleMember -Function New-QOTHelpView
