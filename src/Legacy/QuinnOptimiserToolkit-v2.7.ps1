<#
    Quinn Optimiser Toolkit - WPF UI V3 (Apps tab updated)

    - Dark theme + accent
    - Tweaks & Cleaning tab with individual tweak checkboxes
    - Advanced tab with more options
    - Apps tab:
        * Auto-scan on load
        * Manual “Uninstall selected” only
        * Install common apps via winget with per-row Install button
        * Status bar + buttons disabled while busy
#>

# ------------------------------
# Admin check and assemblies
# ------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Please run this script as Administrator.", "Quinn Optimiser Toolkit", 'OK', 'Error') | Out-Null
    return
}

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

# ------------------------------
# Logging
# ------------------------------
$ToolkitRoot  = "C:\IT"
if (-not (Test-Path $ToolkitRoot)) { New-Item -Path $ToolkitRoot -ItemType Directory -Force | Out-Null }
$LogFile      = Join-Path $ToolkitRoot "QuinnOptimiserToolkit.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value ("[{0}] [{1}] {2}" -f $timestamp, $Level, $Message)
}

Write-Log "===== Quinn Optimiser Toolkit (WPF) started ====="

# ------------------------------
# PLACEHOLDER: ACTION FUNCTIONS
# (wire your existing logic into these)
# ------------------------------
# Cleaning
function Action-CleanWindowsUpdateCache   { Write-Log "Clean Windows Update cache (TODO: wire in existing logic)" }
function Action-CleanDeliveryOptimisation { Write-Log "Clean Delivery Optimisation cache (TODO)" }
function Action-ClearTempFolders          { Write-Log "Clear temp folders (TODO)" }
function Action-WinSxSSafeCleanup         { Write-Log "WinSxS safe cleanup (TODO)" }
function Action-RemoveWindowsOld          { Write-Log "Remove Windows.old (TODO)" }
function Action-RemoveOldRestorePoints    { Write-Log "Remove old restore points (TODO)" }
function Action-RemoveDumpsAndLogs        { Write-Log "Remove dumps and logs (TODO)" }

# Individual tweaks (safe / debloat)
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

# Advanced
function Action-RemoveOldProfiles         { Write-Log "Remove old user profiles (TODO)" }
function Action-AdvancedRestoreAggressive { Write-Log "Aggressive restore point / log cleanup (TODO)" }
function Action-AdvancedDeepCache         { Write-Log "Deep cache cleanup (component store etc) (TODO)" }
function Action-AdvancedNetworkTweaks     { Write-Log "General network tweaks (TODO)" }
function Action-DisableIPv6               { Write-Log "Disable IPv6 on non tunnel adapters (TODO)" }
function Action-DisableTeredo             { Write-Log "Disable Teredo / 6to4 (TODO)" }
function Action-AdvancedServiceOptimise   { Write-Log "Service tuning / disabling non essential services (TODO)" }
function Action-AdvancedSearchIndex       { Write-Log "Reduce or disable Windows Search indexing (TODO)" }

# ------------------------------
# App scan and risk logic
# ------------------------------
$Global:AppWhitelistPatterns = @(
    "Genesys",
    "GenesysCloud",
    "FortiClient",
    "Fortinet",
    "ScreenConnect",
    "ConnectWise",
    "Sophos",
    "Microsoft 365",
    "Microsoft Office",
    "Teams",
    "Word",
    "PowerPoint",
    "Outlook"
)

function Get-InstalledApps {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $apps = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $_.DisplayName) { return }

            $isSystem = $false
            if ($_.SystemComponent -eq 1) { $isSystem = $true }
            if ($_.ReleaseType -eq "Security Update" -or $_.ParentKeyName) { $isSystem = $true }
            if ($_.DisplayName -match "Driver|Runtime|Redistributable|Update|Hotfix") { $isSystem = $true }
            if ($_.Publisher -match "Microsoft|Intel|NVIDIA|Realtek|AMD") { $isSystem = $true }

            $sizeMB = $null
            if ($_.EstimatedSize) { $sizeMB = [math]::Round($_.EstimatedSize / 1024, 1) }

            $installDate = $null
            if ($_.InstallDate -and $_.InstallDate -match "^\d{8}$") {
                $installDate = [datetime]::ParseExact($_.InstallDate, "yyyyMMdd", $null)
            }

            $isWhitelisted = $false
            foreach ($pattern in $Global:AppWhitelistPatterns) {
                if ($_.DisplayName -like "*$pattern*") { $isWhitelisted = $true; break }
            }

            [PSCustomObject]@{
                Name           = $_.DisplayName
                Publisher      = $_.Publisher
                SizeMB         = $sizeMB
                InstallDate    = $installDate
                IsSystem       = $isSystem
                IsWhitelisted  = $isWhitelisted
                UninstallString= $_.UninstallString
                LastUsed       = $installDate
            }
        }
    }
    $apps | Sort-Object Name -Unique
}

function Get-AppRisk {
    param($App)

    if ($App.IsWhitelisted) { return "Protected" }
    if ($App.IsSystem -or -not $App.UninstallString) { return "Red" }

    $days = $null
    if ($App.InstallDate) {
        $days = (New-TimeSpan -Start $App.InstallDate -End (Get-Date)).Days
    }

    if ($App.SizeMB -ge 500 -or $days -ge 365) { return "Amber" }
    return "Green"
}

# ------------------------------
# System summary
# ------------------------------
function Get-SystemSummaryText {
    $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    if (-not $drive) { return "C drive: not found" }

    $totalBytes = $drive.Used + $drive.Free
    if ($totalBytes -le 0) {
        return "C: capacity could not be calculated"
    }

    $usedGB  = [math]::Round($drive.Used  / 1GB, 1)
    $freeGB  = [math]::Round($drive.Free  / 1GB, 1)
    $totalGB = [math]::Round($totalBytes  / 1GB, 1)
    $freePct = [math]::Round(($drive.Free / $totalBytes) * 100, 1)

    "C: {0} GB used / {1} GB free ({2} GB total, {3}% free)" -f $usedGB, $freeGB, $totalGB, $freePct
}

# ------------------------------
# Install apps (winget) helpers
# ------------------------------
function Test-AppInstalledWinget {
    param(
        [string]$Id
    )
    try {
        $result = winget list --id $Id --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($Id)) {
            return $true
        }
    } catch {
        Write-Log "winget list failed for ${Id}: $($_.Exception.Message)" "WARN"
    }
    return $false
}

function Install-AppWithWinget {
    param(
        $AppRow,
        [System.Windows.Controls.DataGrid]$InstallGrid
    )

    if (-not $AppRow -or -not $AppRow.WingetId) { return }

    Write-Log "Requested install: $($AppRow.Name) [$($AppRow.WingetId)]"
    Set-Status "Installing $($AppRow.Name)..." 0 $true

    try {
        $AppRow.Status = "Installing..."
        $InstallGrid.Items.Refresh()

        $cmd = "winget install --id `"$($AppRow.WingetId)`" -h --accept-source-agreements --accept-package-agreements"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden

# Update fields instantly for the UI
$AppRow.Status         = "Installed this session"
$AppRow.InstallLabel   = "Installed"
$AppRow.IsInstallable  = $false
$AppRow.InstallTooltip = "Already installed"

Write-Log "Install completed: $($AppRow.Name)"

# Refresh UI row (safe dispatcher call)
$InstallGrid.Dispatcher.Invoke({
    $InstallGrid.Items.Refresh()
})

    } catch {
        $AppRow.Status = "Install failed"
        Write-Log "Install failed for $($AppRow.Name): $($_.Exception.Message)" "ERROR"
    }

    $InstallGrid.Items.Refresh()
    Set-Status "Idle" 0 $false
}

function Initialise-InstallAppsList {
    param(
        [System.Collections.ObjectModel.ObservableCollection[object]]$Collection
    )

    $definitions = @(
        @{ Name = "Google Chrome";      WingetId = "Google.Chrome"              }
        @{ Name = "Mozilla Firefox";    WingetId = "Mozilla.Firefox"            }
        @{ Name = "7-Zip";              WingetId = "7zip.7zip"                  }
        @{ Name = "VLC Media Player";   WingetId = "VideoLAN.VLC"               }
        @{ Name = "Notepad++";          WingetId = "Notepad++.Notepad++"        }
        @{ Name = "Discord";            WingetId = "Discord.Discord"            }
        @{ Name = "Spotify";            WingetId = "Spotify.Spotify"            }
        @{ Name = "Visual Studio Code"; WingetId = "Microsoft.VisualStudioCode" }
    )

$Collection.Clear()

foreach ($def in $definitions) {
    $status = "Not installed"
    if (Test-AppInstalledWinget -Id $def.WingetId) {
        $status = "Installed"
    }

    $isInstalled  = ($status -eq "Installed")

    $obj = [pscustomobject]@{
        IsSelected      = $false
        Name            = $def.Name
        WingetId        = $def.WingetId
        Status          = $status

        # New fields used by the XAML bindings
        InstallLabel    = if ($isInstalled) { "Installed" } else { "Install" }
        IsInstallable   = -not $isInstalled
        InstallTooltip  = if ($isInstalled) { "Already installed" } else { "Click to install" }
    }

    $Collection.Add($obj) | Out-Null
}

Write-Log "Initialised InstallApps list with $($Collection.Count) entries."
}
function Install-SelectedCommonApps {
    param(
        [System.Collections.ObjectModel.ObservableCollection[object]]$Collection,
        [System.Windows.Controls.DataGrid]$Grid
    )

    # Find all ticked rows in the bottom grid
    $selected = $Collection | Where-Object { $_.IsSelected }

    if (-not $selected) {
        [System.Windows.MessageBox]::Show(
            "No apps ticked in the list.",
            "Install common apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $names = $selected.Name -join ", "
    $confirm = [System.Windows.MessageBox]::Show(
        "Install the following app(s)?`n`n$names",
        "Confirm install",
        'YesNo',
        'Question'
    )

    if ($confirm -ne 'Yes') { return }

    Set-Status "Installing selected apps..." 0 $true
    Write-Log "Starting bulk install for common apps: $names"

    foreach ($app in $selected) {
        Install-AppWithWinget -AppRow $app -InstallGrid $Grid
    }

    # Rebuild list so statuses reflect current state
    Initialise-InstallAppsList -Collection $Collection

    Set-Status "Idle" 0 $false
}

# ------------------------------
# WPF XAML
# ------------------------------
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Quinn Optimiser Toolkit" Height="650" Width="1000" Background="#0F172A"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <SolidColorBrush x:Key="AccentBrush"   Color="#2563EB"/>
        <SolidColorBrush x:Key="CardBrush"     Color="#020617"/>
        <SolidColorBrush x:Key="BorderBrush"   Color="#374151"/>

        <SolidColorBrush x:Key="SafeBrush"     Color="#16A34A"/>
        <SolidColorBrush x:Key="CautionBrush"  Color="#F59E0B"/>
        <SolidColorBrush x:Key="DangerBrush"   Color="#DC2626"/>

        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Margin" Value="10"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Background" Value="{StaticResource CardBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="HeaderTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <TextBlock Text="{Binding}" Foreground="{StaticResource AccentBrush}" FontWeight="Bold"/>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Button">
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Padding" Value="6,3"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
        </Style>

        <Style TargetType="TabControl">
            <Setter Property="Margin" Value="10"/>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#111827"/>
            <Setter Property="Margin" Value="0,0,2,0"/>
            <Setter Property="Padding" Value="10,4"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#FFFFFF"/>
                    <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header / mode -->
        <Border Grid.Row="0" Background="#020617" Padding="10" BorderBrush="#111827" BorderThickness="0,0,0,1">
            <DockPanel>
                <StackPanel Orientation="Vertical" DockPanel.Dock="Left">
                    <TextBlock Text="Quinn Optimiser Toolkit" FontSize="20" Foreground="White" FontWeight="Bold"/>
                    <TextBlock x:Name="SummaryText" Text="Loading system summary..." Foreground="#9CA3AF" FontSize="11"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" VerticalAlignment="Center">
                    <TextBlock Text="Mode:" Foreground="White" Margin="0,0,5,0" VerticalAlignment="Center"/>
                    <ComboBox x:Name="ModeCombo" Width="200" SelectedIndex="0">
                        <ComboBoxItem Content="Custom selection"/>
                        <ComboBoxItem Content="Clean only"/>
                        <ComboBoxItem Content="Debloat only"/>
                        <ComboBoxItem Content="Performance tune"/>
                        <ComboBoxItem Content="Full optimisation"/>
                    </ComboBox>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Main tabs -->
        <TabControl Grid.Row="1" x:Name="MainTabs">
            <!-- Tweaks tab now also includes Cleaning -->
            <TabItem Header="Tweaks &amp; Cleaning">
                <!-- push content down so sub headings are not clipped -->
                <Grid Margin="5,20,5,5">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Cleaning & Maintenance -->
                    <GroupBox Header="Cleaning &amp; Maintenance" Grid.Row="0" Grid.Column="0">
                        <StackPanel>
                            <CheckBox x:Name="CbCleanWU"    Content="Clean Windows Update cache"                    Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                            <CheckBox x:Name="CbCleanDO"    Content="Clean Delivery Optimisation cache"            Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                            <CheckBox x:Name="CbTemp"       Content="Clear temp folders"                           Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                            <CheckBox x:Name="CbWinSxS"     Content="WinSxS safe cleanup"                          Foreground="{StaticResource CautionBrush}" Margin="3"/>
                            <CheckBox x:Name="CbWinOld"     Content="Remove Windows.old (if present)"              Foreground="{StaticResource CautionBrush}" Margin="3"/>
                            <CheckBox x:Name="CbLogs"       Content="Clear logs, dumps and old restore points"     Foreground="{StaticResource CautionBrush}" Margin="3"/>
                        </StackPanel>
                    </GroupBox>

                    <!-- Tweaks & Privacy: individual options -->
                    <GroupBox Header="Tweaks &amp; Privacy" Grid.Row="0" Grid.Column="1">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel>
                                <CheckBox x:Name="CbT_StartMenuRec"   Content="Disable Start menu recommendations"                         Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_SuggestedApps"  Content="Disable suggested apps and Microsoft promotional content"   Foreground="{StaticResource CautionBrush}" Margin="3"/>
                                <CheckBox x:Name="CbT_Widgets"        Content="Disable Widgets"                                           Foreground="{StaticResource CautionBrush}" Margin="3"/>
                                <CheckBox x:Name="CbT_News"           Content="Disable News &amp; Interests"                              Foreground="{StaticResource CautionBrush}" Margin="3"/>
                                <CheckBox x:Name="CbT_BackgroundApps" Content="Limit or disable background apps"                          Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_Animations"     Content="Reduce or disable Windows animations"                      Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_Tips"           Content="Turn off online tips and suggestions"                      Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_AdId"           Content="Disable advertising ID"                                    Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_Feedback"       Content="Disable Feedback Hub prompts"                              Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_Telemetry"      Content="Set telemetry to a safe / minimal level"                   Foreground="{StaticResource CautionBrush}" Margin="3"/>
                                <CheckBox x:Name="CbT_MeetNow"        Content="Turn off Meet Now"                                        Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_Cortana"        Content="Turn off Cortana leftovers"                               Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_StockApps"      Content="Remove unused stock apps (3D Viewer, Mixed Reality Portal…)" Foreground="{StaticResource CautionBrush}" Margin="3"/>
                                <CheckBox x:Name="CbT_StartupSound"   Content="Turn off startup sound"                                   Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_SnapAssist"     Content="Turn off or customise Snap Assist"                         Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_MouseAccel"     Content="Turn off mouse acceleration"                               Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_HiddenFiles"    Content="Show hidden files and file extensions"                     Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_VerboseLogon"   Content="Enable verbose logon messages"                             Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_GameDVR"        Content="Disable GameDVR"                                          Foreground="{StaticResource SafeBrush}"    Margin="3"/>
                                <CheckBox x:Name="CbT_AppReinstall"   Content="Disable auto reinstall of apps after updates"              Foreground="{StaticResource CautionBrush}" Margin="3"/>
                            </StackPanel>
                        </ScrollViewer>
                    </GroupBox>

                    <!-- Notes -->
                    <GroupBox Header="Notes" Grid.Row="1" Grid.ColumnSpan="2">
                        <TextBlock TextWrapping="Wrap" Foreground="#9CA3AF">
                            Green items are safe and reversible. Amber items should be used with a restore point and basic understanding of the impact.
                            Advanced and expert tweaks live under the Advanced tab.
                        </TextBlock>
                    </GroupBox>
                </Grid>
            </TabItem>

            <!-- Apps tab with scan + install -->
            <TabItem Header="Apps">
                <Grid Margin="5,20,5,5">
                    <Grid.RowDefinitions>
                        <!-- Row 0 = buttons, Row 1 = content -->
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Top bar: scan + uninstall -->
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,5">
                        <Button x:Name="BtnScanApps"
                                Content="Rescan installed apps"
                                Width="170"
                                MinWidth="170"
                                Padding="10,4"
                                HorizontalContentAlignment="Center"/>
                        <Button x:Name="BtnUninstallSelected"
                                Content="Uninstall selected"
                                Width="170"
                                MinWidth="170"
                                Padding="10,4"
                                Margin="5,0,0,0"
                                HorizontalContentAlignment="Center"/>
                        <TextBlock Text="  Green = safe, Amber = caution, Red = system/experts only. Whitelisted apps cannot be selected."
                                   Foreground="#9CA3AF"
                                   VerticalAlignment="Center"
                                   Margin="10,0,0,0"/>
                    </StackPanel>

                    <!-- Two evenly sized boxes underneath -->
                    <Grid Grid.Row="1">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <!-- Installed apps (uninstall) -->
                        <GroupBox Header="Installed apps"
                                  Grid.Row="0"
                                  Margin="0,0,0,5">
                            <DataGrid x:Name="AppsGrid"
                                      AutoGenerateColumns="False"
                                      CanUserAddRows="False"
                                      GridLinesVisibility="Horizontal"
                                      HeadersVisibility="Column"
                                      Background="{StaticResource CardBrush}"
                                      Foreground="White"
                                      BorderBrush="{StaticResource BorderBrush}"
                                      RowBackground="#0B1120"
                                      AlternatingRowBackground="#020617">
                                <DataGrid.Resources>
                                    <Style TargetType="DataGridColumnHeader">
                                        <Setter Property="Background" Value="#020617"/>
                                        <Setter Property="Foreground" Value="White"/>
                                        <Setter Property="FontWeight" Value="Bold"/>
                                        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
                                    </Style>
                                    <Style TargetType="DataGridCell">
                                        <Setter Property="Foreground" Value="White"/>
                                        <Setter Property="Background" Value="Transparent"/>
                                    </Style>
                                    <Style TargetType="DataGridRow">
                                        <Setter Property="Foreground" Value="White"/>
                                        <Setter Property="BorderThickness" Value="0,0,0,1"/>
                                        <Style.Triggers>
                                            <DataTrigger Binding="{Binding Risk}" Value="Green">
                                                <Setter Property="BorderBrush" Value="{StaticResource SafeBrush}"/>
                                            </DataTrigger>
                                            <DataTrigger Binding="{Binding Risk}" Value="Amber">
                                                <Setter Property="BorderBrush" Value="{StaticResource CautionBrush}"/>
                                            </DataTrigger>
                                            <DataTrigger Binding="{Binding Risk}" Value="Red">
                                                <Setter Property="BorderBrush" Value="{StaticResource DangerBrush}"/>
                                            </DataTrigger>
                                            <DataTrigger Binding="{Binding Risk}" Value="Protected">
                                                <Setter Property="Opacity" Value="0.7"/>
                                            </DataTrigger>
                                        </Style.Triggers>
                                    </Style>
                                </DataGrid.Resources>

                                <DataGrid.Columns>
                                    <DataGridTemplateColumn Header="Select" Width="60">
                                        <DataGridTemplateColumn.CellTemplate>
                                            <DataTemplate>
                                                <CheckBox IsChecked="{Binding IsSelected}"
                                                          IsEnabled="{Binding IsSelectable}"
                                                          HorizontalAlignment="Center"/>
                                            </DataTemplate>
                                        </DataGridTemplateColumn.CellTemplate>
                                    </DataGridTemplateColumn>
                                    <DataGridTextColumn Header="Name"      Binding="{Binding Name}"       Width="*"/>
                                    <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}"  Width="200"/>
                                    <DataGridTextColumn Header="Size (MB)" Binding="{Binding SizeMB}"     Width="90"/>
                                    <DataGridTextColumn Header="Installed" Binding="{Binding InstallDate, StringFormat=d}" Width="100"/>
                                    <DataGridTextColumn Header="Risk"      Binding="{Binding Risk}"       Width="90"/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </GroupBox>

                        <!-- Install common apps -->
                        <GroupBox Header="Install common apps (winget)"
                                  Grid.Row="1"
                                  Margin="0,5,0,0">
                            <DataGrid x:Name="InstallGrid"
                                      AutoGenerateColumns="False"
                                      CanUserAddRows="False"
                                      GridLinesVisibility="Horizontal"
                                      HeadersVisibility="Column"
                                      Background="{StaticResource CardBrush}"
                                      Foreground="White"
                                      BorderBrush="{StaticResource BorderBrush}"
                                      RowBackground="#0B1120"
                                      AlternatingRowBackground="#020617">
                                <DataGrid.Resources>
                                    <Style TargetType="DataGridColumnHeader">
                                        <Setter Property="Background" Value="#020617"/>
                                        <Setter Property="Foreground" Value="White"/>
                                        <Setter Property="FontWeight" Value="Bold"/>
                                        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
                                    </Style>
                                    <Style TargetType="DataGridCell">
                                        <Setter Property="Foreground" Value="White"/>
                                        <Setter Property="Background" Value="Transparent"/>
                                    </Style>
                                </DataGrid.Resources>

                                <DataGrid.Columns>
<DataGridTemplateColumn Header="Select" Width="60">
    <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
            <CheckBox IsChecked="{Binding IsSelected}"
                      HorizontalAlignment="Center"/>
        </DataTemplate>
    </DataGridTemplateColumn.CellTemplate>
</DataGridTemplateColumn>
                                    <DataGridTextColumn Header="Name"
                                                        Binding="{Binding Name}"
                                                        Width="*"/>
                                    <DataGridTextColumn Header="Status"
                                                        Binding="{Binding Status}"
                                                        Width="180"/>
<DataGridTemplateColumn Header="Install" Width="110">
    <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
            <Button Content="{Binding InstallLabel}"
                    Padding="4,1"
                    Margin="2"
                    IsEnabled="{Binding IsInstallable}">
                <Button.ToolTip>
                    <TextBlock Text="{Binding InstallTooltip}"/>
                </Button.ToolTip>
            </Button>
        </DataTemplate>
    </DataGridTemplateColumn.CellTemplate>
</DataGridTemplateColumn>

                                </DataGrid.Columns>
                            </DataGrid>
                        </GroupBox>
                    </Grid>
                </Grid>
            </TabItem>

            <!-- Advanced tab -->
            <TabItem Header="Advanced">
                <!-- push content down so headings don't sit under the tab strip -->
                <Grid Margin="5,20,5,5">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <GroupBox Header="Advanced cleaning &amp; profiles" Grid.Row="0" Grid.Column="0">
                        <StackPanel>
                            <CheckBox x:Name="CbAdvProfiles"   Content="Remove old user profiles (keeping current + admin accounts)"   Foreground="{StaticResource CautionBrush}" Margin="3"/>
                            <CheckBox x:Name="CbAdvRestore"    Content="Aggressive restore point / log clean"                          Foreground="{StaticResource DangerBrush}"  Margin="3"/>
                            <CheckBox x:Name="CbAdvDeepCache"  Content="Deep cache cleanup (WinSxS / component store - experts only)"  Foreground="{StaticResource DangerBrush}"  Margin="3"/>
                        </StackPanel>
                    </GroupBox>

                    <GroupBox Header="Network &amp; services" Grid.Row="0" Grid.Column="1">
                        <StackPanel>
                            <CheckBox x:Name="CbAdvNet"        Content="General network tweaks (DNS / MTU / offloads)"                 Foreground="{StaticResource CautionBrush}" Margin="3"/>
                            <CheckBox x:Name="CbAdvIPv6"       Content="Disable IPv6 on non-tunnel adapters"                            Foreground="{StaticResource DangerBrush}"  Margin="3"/>
                            <CheckBox x:Name="CbAdvTeredo"     Content="Disable Teredo and 6to4 tunnels"                               Foreground="{StaticResource DangerBrush}"  Margin="3"/>
                            <CheckBox x:Name="CbAdvServices"   Content="Service optimisation (disabling non-essential services)"        Foreground="{StaticResource CautionBrush}" Margin="3"/>
                            <CheckBox x:Name="CbAdvSearchIndex" Content="Reduce or disable Windows Search indexing"                     Foreground="{StaticResource CautionBrush}" Margin="3"/>
                        </StackPanel>
                    </GroupBox>

                    <GroupBox Header="Warnings" Grid.Row="1" Grid.ColumnSpan="2">
                        <TextBlock TextWrapping="Wrap" Foreground="{StaticResource DangerBrush}">
                            All advanced options are higher risk and aimed at experienced users. 
                            A backup and restore point are strongly recommended before enabling these.
                        </TextBlock>
                    </GroupBox>
                </Grid>
            </TabItem>
        </TabControl>

        <!-- Status bar -->
        <Border Grid.Row="2" Background="#020617" Padding="6" BorderBrush="#111827" BorderThickness="1,1,1,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                    <TextBlock Text="Status: " Foreground="#9CA3AF"/>
                    <TextBlock x:Name="StatusLabel" Text="Idle" Foreground="White"/>
                </StackPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="RunButton" Content="Run selected actions" Margin="0,0,10,0" Width="160"/>
                    <ProgressBar x:Name="MainProgress" Width="200" Height="16" Minimum="0" Maximum="100" Value="0"/>
                </StackPanel>
            </DockPanel>
        </Border>
    </Grid>
</Window>
"@

# ------------------------------
# Load WPF window
# ------------------------------
$window = [Windows.Markup.XamlReader]::Parse($xaml)

# Controls
$StatusLabel   = $window.FindName("StatusLabel")
$SummaryText   = $window.FindName("SummaryText")
$MainProgress  = $window.FindName("MainProgress")
$RunButton     = $window.FindName("RunButton")
$ModeCombo     = $window.FindName("ModeCombo")

$CbCleanWU     = $window.FindName("CbCleanWU")
$CbCleanDO     = $window.FindName("CbCleanDO")
$CbTemp        = $window.FindName("CbTemp")
$CbWinSxS      = $window.FindName("CbWinSxS")
$CbWinOld      = $window.FindName("CbWinOld")
$CbLogs        = $window.FindName("CbLogs")

# tweak checkboxes
$CbT_StartMenuRec   = $window.FindName("CbT_StartMenuRec")
$CbT_SuggestedApps  = $window.FindName("CbT_SuggestedApps")
$CbT_Widgets        = $window.FindName("CbT_Widgets")
$CbT_News           = $window.FindName("CbT_News")
$CbT_BackgroundApps = $window.FindName("CbT_BackgroundApps")
$CbT_Animations     = $window.FindName("CbT_Animations")
$CbT_Tips           = $window.FindName("CbT_Tips")
$CbT_AdId           = $window.FindName("CbT_AdId")
$CbT_Feedback       = $window.FindName("CbT_Feedback")
$CbT_Telemetry      = $window.FindName("CbT_Telemetry")
$CbT_MeetNow        = $window.FindName("CbT_MeetNow")
$CbT_Cortana        = $window.FindName("CbT_Cortana")
$CbT_StockApps      = $window.FindName("CbT_StockApps")
$CbT_StartupSound   = $window.FindName("CbT_StartupSound")
$CbT_SnapAssist     = $window.FindName("CbT_SnapAssist")
$CbT_MouseAccel     = $window.FindName("CbT_MouseAccel")
$CbT_HiddenFiles    = $window.FindName("CbT_HiddenFiles")
$CbT_VerboseLogon   = $window.FindName("CbT_VerboseLogon")
$CbT_GameDVR        = $window.FindName("CbT_GameDVR")
$CbT_AppReinstall   = $window.FindName("CbT_AppReinstall")

# advanced
$CbAdvProfiles     = $window.FindName("CbAdvProfiles")
$CbAdvRestore      = $window.FindName("CbAdvRestore")
$CbAdvDeepCache    = $window.FindName("CbAdvDeepCache")
$CbAdvNet          = $window.FindName("CbAdvNet")
$CbAdvIPv6         = $window.FindName("CbAdvIPv6")
$CbAdvTeredo       = $window.FindName("CbAdvTeredo")
$CbAdvServices     = $window.FindName("CbAdvServices")
$CbAdvSearchIndex  = $window.FindName("CbAdvSearchIndex")

# apps tab
$AppsGrid      = $window.FindName("AppsGrid")
$BtnScanApps   = $window.FindName("BtnScanApps")
$BtnUninstallSelected = $window.FindName("BtnUninstallSelected")
$InstallGrid   = $window.FindName("InstallGrid")

# ------------------------------
# Status helper
# ------------------------------
function Set-Status {
    param(
        [string]$Text,
        [int]$Progress = 0,
        [bool]$Busy = $false
    )

    if ($StatusLabel) { $StatusLabel.Text = $Text }
    if ($MainProgress) {
        $MainProgress.Value = $Progress
        $MainProgress.IsIndeterminate = $Busy
    }

    if ($Busy) {
        if ($RunButton)            { $RunButton.IsEnabled = $false }
        if ($BtnScanApps)          { $BtnScanApps.IsEnabled = $false }
        if ($BtnUninstallSelected) { $BtnUninstallSelected.IsEnabled = $false }
    } else {
        if ($RunButton)            { $RunButton.IsEnabled = $true }
        if ($BtnScanApps)          { $BtnScanApps.IsEnabled = $true }
        if ($BtnUninstallSelected) { $BtnUninstallSelected.IsEnabled = $true }
    }
}

$SummaryText.Text = Get-SystemSummaryText

# ------------------------------
# Collections for grids
# ------------------------------
$Global:AppsCollection        = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$Global:InstallAppsCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]

$AppsGrid.ItemsSource    = $Global:AppsCollection
$InstallGrid.ItemsSource = $Global:InstallAppsCollection

# ------------------------------
# Mode presets
# ------------------------------
$allCheckboxes = @(
    $CbCleanWU,$CbCleanDO,$CbTemp,$CbWinSxS,$CbWinOld,$CbLogs,
    $CbT_StartMenuRec,$CbT_SuggestedApps,$CbT_Widgets,$CbT_News,
    $CbT_BackgroundApps,$CbT_Animations,$CbT_Tips,$CbT_AdId,$CbT_Feedback,
    $CbT_Telemetry,$CbT_MeetNow,$CbT_Cortana,$CbT_StockApps,$CbT_StartupSound,
    $CbT_SnapAssist,$CbT_MouseAccel,$CbT_HiddenFiles,$CbT_VerboseLogon,
    $CbT_GameDVR,$CbT_AppReinstall,
    $CbAdvProfiles,$CbAdvRestore,$CbAdvDeepCache,$CbAdvNet,$CbAdvIPv6,$CbAdvTeredo,$CbAdvServices,$CbAdvSearchIndex
)

$ModeCombo.Add_SelectionChanged({
    foreach ($cb in $allCheckboxes) {
        if ($cb) { $cb.IsChecked = $false }
    }

    $mode = ($ModeCombo.SelectedItem.Content)
    switch ($mode) {
        "Clean only" {
            $CbCleanWU.IsChecked  = $true
            $CbCleanDO.IsChecked  = $true
            $CbTemp.IsChecked     = $true
            $CbWinSxS.IsChecked   = $true
            $CbWinOld.IsChecked   = $true
            $CbLogs.IsChecked     = $true
        }
        "Debloat only" {
            $CbT_SuggestedApps.IsChecked = $true
            $CbT_Widgets.IsChecked       = $true
            $CbT_News.IsChecked          = $true
            $CbT_StockApps.IsChecked     = $true
            $CbT_AppReinstall.IsChecked  = $true
        }
        "Performance tune" {
            $CbT_BackgroundApps.IsChecked = $true
            $CbT_Animations.IsChecked     = $true
            $CbT_Tips.IsChecked           = $true
            $CbT_AdId.IsChecked           = $true
            $CbT_Feedback.IsChecked       = $true
            $CbT_MeetNow.IsChecked        = $true
            $CbT_StartupSound.IsChecked   = $true
            $CbT_SnapAssist.IsChecked     = $true
            $CbT_MouseAccel.IsChecked     = $true
            $CbT_HiddenFiles.IsChecked    = $true
            $CbT_VerboseLogon.IsChecked   = $true
            $CbT_GameDVR.IsChecked        = $true
        }
        "Full optimisation" {
            foreach ($cb in @(
                $CbCleanWU,$CbCleanDO,$CbTemp,$CbWinSxS,$CbWinOld,$CbLogs,
                $CbT_StartMenuRec,$CbT_SuggestedApps,$CbT_Widgets,$CbT_News,
                $CbT_BackgroundApps,$CbT_Animations,$CbT_Tips,$CbT_AdId,$CbT_Feedback,
                $CbT_Telemetry,$CbT_MeetNow,$CbT_Cortana,$CbT_StockApps,$CbT_StartupSound,
                $CbT_SnapAssist,$CbT_MouseAccel,$CbT_HiddenFiles,$CbT_VerboseLogon,
                $CbT_GameDVR,$CbT_AppReinstall
            )) { $cb.IsChecked = $true }
        }
        default { }
    }
})

# ------------------------------
# Apps tab behaviour
# ------------------------------
function Refresh-InstalledApps {
    Set-Status "Scanning apps..." 0 $true
    $Global:AppsCollection.Clear()
    Write-Log "Started scan for installed apps."

    $apps = Get-InstalledApps
    foreach ($a in $apps) {
        $risk = Get-AppRisk -App $a
        $obj = [pscustomobject]@{
            IsSelected    = $false
            IsSelectable  = -not $a.IsWhitelisted -and $risk -ne "Red"
            Name          = $a.Name
            Publisher     = $a.Publisher
            SizeMB        = $a.SizeMB
            InstallDate   = $a.InstallDate
            Risk          = $risk
            Uninstall     = $a.UninstallString
            IsWhitelisted = $a.IsWhitelisted
        }
        $Global:AppsCollection.Add($obj) | Out-Null
    }

    $AppsGrid.Items.Refresh()
    Write-Log "Finished scan for installed apps. Count: $($Global:AppsCollection.Count)"
    Set-Status "Idle" 0 $false
}

# Rescan button
$BtnScanApps.Add_Click({
    Refresh-InstalledApps
    Initialise-InstallAppsList -Collection $Global:InstallAppsCollection
})

# Uninstall selected (manual only)

# Uninstall selected (with proper whitelist + refresh + logging)
$BtnUninstallSelected.Add_Click({
    # 1. Grab everything the user actually ticked
    $chosen = $Global:AppsCollection | Where-Object { $_.IsSelected }

    if (-not $chosen) {
        [System.Windows.MessageBox]::Show(
            "No apps selected.",
            "Apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    # 2. Work out what is protected vs uninstallable
    #    Protected = on whitelist OR Risk = Red OR no uninstall string
    $protected = $chosen | Where-Object {
        $_.IsWhitelisted -or
        $_.Risk -eq "Red" -or
        -not $_.Uninstall
    }

    $toRemove = $chosen | Where-Object {
        -not ($_.IsWhitelisted -or $_.Risk -eq "Red" -or -not $_.Uninstall)
    }

    # 3. If *everything* selected is protected, bail with a clear message
    if (-not $toRemove) {
        [System.Windows.MessageBox]::Show(
            "All selected apps are on the protection whitelist or are system components.`n`nNothing will be uninstalled.",
            "Apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    # Optional: tell the user which ones are protected but won’t be touched
    if ($protected) {
        $protNames = ($protected.Name -join ", ")
        Write-Log "Protected apps in selection (skipped): $protNames"
    }

    $names = ($toRemove.Name -join ", ")

    $confirm = [System.Windows.MessageBox]::Show(
        "Uninstall the following apps?`n`n$names",
        "Confirm uninstall",
        'YesNo',
        'Warning'
    )
    if ($confirm -ne 'Yes') { return }

    # 4. Status + logging
    Set-Status "Uninstalling selected apps..." 0 $true
    Write-Log "Starting uninstall of selected apps: $names"

    $count = $toRemove.Count
    if ($count -lt 1) { $count = 1 }   # safety against divide-by-zero
    $i = 0
    $failures = @()

    foreach ($app in $toRemove) {
        $i++
        $pct = [int](($i / $count) * 100)
        Set-Status ("Uninstalling {0} ({1}/{2})" -f $app.Name, $i, $count) $pct $true
        Write-Log "Attempting uninstall: $($app.Name)"

        try {
            $cmd = $app.Uninstall
            if (-not $cmd) {
                Write-Log "No UninstallString for $($app.Name), skipping." "WARN"
                $failures += $app.Name
                continue
            }

            $cmd  = $cmd.Trim()
            $exe  = $null
            $args = ""

            # If it starts with a quoted path: "C:\Path\uninstall.exe" /foo
            if ($cmd.StartsWith('"')) {
                $secondQuote = $cmd.IndexOf('"', 1)
                if ($secondQuote -gt 0) {
                    $exe  = $cmd.Substring(1, $secondQuote - 1)
                    $args = $cmd.Substring($secondQuote + 1).Trim()
                }
            }

            # Fallback: split on first space
            if (-not $exe) {
                $parts = $cmd.Split(" ", 2, [System.StringSplitOptions]::RemoveEmptyEntries)
                $exe   = $parts[0]
                if ($parts.Count -gt 1) { $args = $parts[1] }
            }

            if (-not (Test-Path $exe)) {
                # Last resort: run exactly as stored via cmd
                Write-Log "Exe path '$exe' not found for $($app.Name), running raw command via cmd." "WARN"
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden
            }
            elseif ($exe -match "msiexec\.exe") {
                # MSI: make sure it is quiet
                if ($args -notmatch "/quiet" -and $args -notmatch "/qn") {
                    $args = "$args /quiet /norestart"
                }
                Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden
            }
            else {
                # Non-MSI: try to make silent if not already
                if ($args -notmatch "/S" -and
                    $args -notmatch "/silent" -and
                    $args -notmatch "/verysilent" -and
                    $args -notmatch "/quiet")
                {
                    $args = ($args + " /S").Trim()
                }

                Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden
            }

            Write-Log "Uninstall completed for $($app.Name)"
        }
        catch {
            $msg = $_.Exception.Message
            Write-Log "Uninstall failed for $($app.Name): $msg" "ERROR"
            $failures += $app.Name
        }
    }
    # 5. Refresh both lists after uninstall
    Refresh-InstalledApps
    Initialise-InstallAppsList -Collection $Global:InstallAppsCollection

    Set-Status "Idle" 0 $false

    # 6. Only show a popup if there were actual failures
    if ($failures.Count -gt 0) {
        $failedNames = ($failures -join ", ")
        [System.Windows.MessageBox]::Show(
            "Some apps could not be uninstalled:`n`n$failedNames`n`nCheck the log at $LogFile for details.",
            "Apps",
            'OK',
            'Warning'
        ) | Out-Null
    }
})
# Install grid: per-row Install button with bulk support
$InstallGrid.AddHandler(
    [System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($sender, $e)

        $button = $e.OriginalSource
        if (-not ($button -is [System.Windows.Controls.Button])) { return }

        $row = $button.DataContext
        if (-not $row) { return }

        # Look for ticked rows in the bottom grid
        $ticked = $Global:InstallAppsCollection | Where-Object { $_.IsSelected }

        if ($ticked -and $ticked.Count -gt 0) {
            # Ensure the clicked row is also included in bulk if not already
            if (-not $row.IsSelected) {
                $row.IsSelected = $true
            }

            Install-SelectedCommonApps -Collection $Global:InstallAppsCollection -Grid $InstallGrid
        }
else {
    # No ticks: single app install
    Install-AppWithWinget -AppRow $row -InstallGrid $InstallGrid

    # Rebuild list so status reflects current state
    Initialise-InstallAppsList -Collection $Global:InstallAppsCollection
}
    }
)

# Initialise install list and auto-scan apps when the window loads
Initialise-InstallAppsList -Collection $Global:InstallAppsCollection

$window.Add_Loaded({
    Refresh-InstalledApps
})

# ------------------------------
# Run selected actions
# ------------------------------
$RunButton.Add_Click({
    $advancedFlags = @()
    if ($CbAdvProfiles.IsChecked)    { $advancedFlags += "Old profile removal" }
    if ($CbAdvRestore.IsChecked)     { $advancedFlags += "Aggressive restore/log clean" }
    if ($CbAdvDeepCache.IsChecked)   { $advancedFlags += "Deep cache cleanup" }
    if ($CbAdvNet.IsChecked)         { $advancedFlags += "Network tweaks" }
    if ($CbAdvIPv6.IsChecked)        { $advancedFlags += "Disable IPv6" }
    if ($CbAdvTeredo.IsChecked)      { $advancedFlags += "Disable Teredo / 6to4" }
    if ($CbAdvServices.IsChecked)    { $advancedFlags += "Service optimisation" }
    if ($CbAdvSearchIndex.IsChecked) { $advancedFlags += "Search indexing changes" }

    if ($advancedFlags.Count -gt 0) {
        $msg = "You have enabled advanced options:`n`n- " + ($advancedFlags -join "`n- ") + "`n`nThese are higher risk. Continue?"
        $res = [System.Windows.MessageBox]::Show($msg, "Advanced options", 'YesNo', 'Warning')
        if ($res -ne 'Yes') { return }
    }

    Set-Status "Running selected actions..." 0 $true
    Write-Log "Run button pressed."

    try {
        $step = 0
        $bools = @(
            $CbCleanWU,$CbCleanDO,$CbTemp,$CbWinSxS,$CbWinOld,$CbLogs,
            $CbT_StartMenuRec,$CbT_SuggestedApps,$CbT_Widgets,$CbT_News,
            $CbT_BackgroundApps,$CbT_Animations,$CbT_Tips,$CbT_AdId,$CbT_Feedback,
            $CbT_Telemetry,$CbT_MeetNow,$CbT_Cortana,$CbT_StockApps,$CbT_StartupSound,
            $CbT_SnapAssist,$CbT_MouseAccel,$CbT_HiddenFiles,$CbT_VerboseLogon,
            $CbT_GameDVR,$CbT_AppReinstall,
            $CbAdvProfiles,$CbAdvRestore,$CbAdvDeepCache,$CbAdvNet,$CbAdvIPv6,$CbAdvTeredo,$CbAdvServices,$CbAdvSearchIndex
        )

        $maxSteps = ($bools | Where-Object { $_.IsChecked }).Count
        if ($maxSteps -lt 1) { $maxSteps = 1 }

        # Cleaning
        if ($CbCleanWU.IsChecked)   { $step++; Set-Status "Cleaning Windows Update cache..." ([int](($step/$maxSteps)*100)) $true; Action-CleanWindowsUpdateCache }
        if ($CbCleanDO.IsChecked)   { $step++; Set-Status "Cleaning Delivery Optimisation cache..." ([int](($step/$maxSteps)*100)) $true; Action-CleanDeliveryOptimisation }
        if ($CbTemp.IsChecked)      { $step++; Set-Status "Clearing temp folders..." ([int](($step/$maxSteps)*100)) $true; Action-ClearTempFolders }
        if ($CbWinSxS.IsChecked)    { $step++; Set-Status "Running WinSxS safe cleanup..." ([int](($step/$maxSteps)*100)) $true; Action-WinSxSSafeCleanup }
        if ($CbWinOld.IsChecked)    { $step++; Set-Status "Removing Windows.old (if present)..." ([int](($step/$maxSteps)*100)) $true; Action-RemoveWindowsOld }
        if ($CbLogs.IsChecked)      { $step++; Set-Status "Clearing logs, dumps and old restore points..." ([int](($step/$maxSteps)*100)) $true; Action-RemoveDumpsAndLogs }

        # Tweaks
        if ($CbT_StartMenuRec.IsChecked)   { $step++; Set-Status "Tweaking Start menu recommendations..." ([int](($step/$maxSteps)*100)) $true; Action-TweakStartMenuRecommendations }
        if ($CbT_SuggestedApps.IsChecked)  { $step++; Set-Status "Disabling suggested apps and promos..." ([int](($step/$maxSteps)*100)) $true; Action-TweakSuggestedApps }
        if ($CbT_Widgets.IsChecked)        { $step++; Set-Status "Disabling Widgets..." ([int](($step/$maxSteps)*100)) $true; Action-TweakWidgets }
        if ($CbT_News.IsChecked)           { $step++; Set-Status "Disabling News & Interests..." ([int](($step/$maxSteps)*100)) $true; Action-TweakNewsInterests }
        if ($CbT_BackgroundApps.IsChecked) { $step++; Set-Status "Limiting background apps..." ([int](($step/$maxSteps)*100)) $true; Action-TweakBackgroundApps }
        if ($CbT_Animations.IsChecked)     { $step++; Set-Status "Adjusting animations..." ([int](($step/$maxSteps)*100)) $true; Action-TweakAnimations }
        if ($CbT_Tips.IsChecked)           { $step++; Set-Status "Disabling tips and suggestions..." ([int](($step/$maxSteps)*100)) $true; Action-TweakOnlineTips }
        if ($CbT_AdId.IsChecked)           { $step++; Set-Status "Disabling advertising ID..." ([int](($step/$maxSteps)*100)) $true; Action-TweakAdvertisingId }
        if ($CbT_Feedback.IsChecked)       { $step++; Set-Status "Disabling Feedback Hub prompts..." ([int](($step/$maxSteps)*100)) $true; Action-TweakFeedbackHub }
        if ($CbT_Telemetry.IsChecked)      { $step++; Set-Status "Setting telemetry to safe level..." ([int](($step/$maxSteps)*100)) $true; Action-TweakTelemetrySafe }
        if ($CbT_MeetNow.IsChecked)        { $step++; Set-Status "Turning off Meet Now..." ([int](($step/$maxSteps)*100)) $true; Action-TweakMeetNow }
        if ($CbT_Cortana.IsChecked)        { $step++; Set-Status "Turning off Cortana leftovers..." ([int](($step/$maxSteps)*100)) $true; Action-TweakCortanaLeftovers }
        if ($CbT_StockApps.IsChecked)      { $step++; Set-Status "Removing unused stock apps..." ([int](($step/$maxSteps)*100)) $true; Action-RemoveStockApps }
        if ($CbT_StartupSound.IsChecked)   { $step++; Set-Status "Turning off startup sound..." ([int](($step/$maxSteps)*100)) $true; Action-TweakStartupSound }
        if ($CbT_SnapAssist.IsChecked)     { $step++; Set-Status "Tweaking Snap Assist..." ([int](($step/$maxSteps)*100)) $true; Action-TweakSnapAssist }
        if ($CbT_MouseAccel.IsChecked)     { $step++; Set-Status "Disabling mouse acceleration..." ([int](($step/$maxSteps)*100)) $true; Action-TweakMouseAcceleration }
        if ($CbT_HiddenFiles.IsChecked)    { $step++; Set-Status "Showing hidden files and extensions..." ([int](($step/$maxSteps)*100)) $true; Action-ShowHiddenFiles }
        if ($CbT_VerboseLogon.IsChecked)   { $step++; Set-Status "Enabling verbose logon messages..." ([int](($step/$maxSteps)*100)) $true; Action-VerboseLogon }
        if ($CbT_GameDVR.IsChecked)        { $step++; Set-Status "Disabling GameDVR..." ([int](($step/$maxSteps)*100)) $true; Action-DisableGameDVR }
        if ($CbT_AppReinstall.IsChecked)   { $step++; Set-Status "Disabling auto reinstall of apps..." ([int](($step/$maxSteps)*100)) $true; Action-DisableAppReinstall }

        # Advanced
        if ($CbAdvProfiles.IsChecked) {
            $step++; Set-Status "Removing old user profiles..." ([int](($step/$maxSteps)*100)) $true
            Action-RemoveOldProfiles
        }
        if ($CbAdvRestore.IsChecked) {
            $step++; Set-Status "Aggressive restore/log clean..." ([int](($step/$maxSteps)*100)) $true
            Action-AdvancedRestoreAggressive
        }
        if ($CbAdvDeepCache.IsChecked) {
            $step++; Set-Status "Deep cache cleanup..." ([int](($step/$maxSteps)*100)) $true
            Action-AdvancedDeepCache
        }
        if ($CbAdvNet.IsChecked) {
            $step++; Set-Status "Applying network tweaks..." ([int](($step/$maxSteps)*100)) $true
            Action-AdvancedNetworkTweaks
        }
        if ($CbAdvIPv6.IsChecked) {
            $step++; Set-Status "Disabling IPv6..." ([int](($step/$maxSteps)*100)) $true
            Action-DisableIPv6
        }
        if ($CbAdvTeredo.IsChecked) {
            $step++; Set-Status "Disabling Teredo / 6to4..." ([int](($step/$maxSteps)*100)) $true
            Action-DisableTeredo
        }
        if ($CbAdvServices.IsChecked) {
            $step++; Set-Status "Optimising services..." ([int](($step/$maxSteps)*100)) $true
            Action-AdvancedServiceOptimise
        }
        if ($CbAdvSearchIndex.IsChecked) {
            $step++; Set-Status "Adjusting search indexing..." ([int](($step/$maxSteps)*100)) $true
            Action-AdvancedSearchIndex
        }

        Set-Status "Finished" 100 $false
        $SummaryText.Text = Get-SystemSummaryText
        [System.Windows.MessageBox]::Show("All selected actions have finished. Check $LogFile for details.", "Quinn Optimiser Toolkit", 'OK', 'Information') | Out-Null
    }
    catch {
        Write-Log "Error during run: $($_.Exception.Message)" "ERROR"
        Set-Status "Error: $($_.Exception.Message)" 0 $false
        [System.Windows.MessageBox]::Show("Something went wrong, check the log for details.", "Error", 'OK', 'Error') | Out-Null
    }
})

# ------------------------------
# Show window
# ------------------------------
$null = $window.ShowDialog()
Write-Log "===== Quinn Optimiser Toolkit closed ====="
