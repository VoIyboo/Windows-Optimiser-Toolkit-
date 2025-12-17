param(
    [Parameter(Mandatory)]
    [string]$SignalPath,

    [string]$ProgressPath,

    [string]$Title = "Quinn Optimiser Toolkit",
    [string]$Subtitle = "Loading..."
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Simple Studio Voly themed splash, closes when SignalPath exists
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        Width="520"
        Height="220"
        Topmost="True"
        ShowInTaskbar="False">
  <Border CornerRadius="16" Background="#0F172A" BorderBrush="#374151" BorderThickness="1" Padding="18">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
        <TextBlock Text="$Title" Foreground="White" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock Text="$Subtitle" Foreground="#9CA3AF" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>

      <Border Grid.Row="1" Margin="0,18,0,10" Background="#020617" CornerRadius="12" BorderBrush="#374151" BorderThickness="1">
        <Grid Margin="12">
          <ProgressBar Name="BarProgress" IsIndeterminate="False" Minimum="0" Maximum="100" Height="18"/>
          <TextBlock Name="TxtStatus" Text="Starting up..." Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="12"/>
        </Grid>
      </Border>

      <TextBlock Grid.Row="2" Text="Studio Voly" Foreground="#9CA3AF" FontSize="11" HorizontalAlignment="Right"/>
    </Grid>
  </Border>
</Window>
"@

$xml    = [xml]$xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$win    = [Windows.Markup.XamlReader]::Load($reader)

$bar = $win.FindName("BarProgress")
$txt = $win.FindName("TxtStatus")


# Poll for the signal file, then close
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({

    # Read progress updates if a progress file is provided
    if ($ProgressPath -and (Test-Path -LiteralPath $ProgressPath)) {
        try {
            $p = Get-Content -LiteralPath $ProgressPath -Raw | ConvertFrom-Json
            if ($bar -and $p.progress -ne $null) { $bar.Value = [double]$p.progress }
            if ($txt -and $p.status) { $txt.Text = $p.status }
        } catch { }
    }

    # Signal file means we are done
    if (Test-Path -LiteralPath $SignalPath) {
        $timer.Stop()
        try { Remove-Item -LiteralPath $SignalPath -Force -ErrorAction SilentlyContinue } catch {}
        $win.Close()
    }

})
$timer.Start()

$null = $win.ShowDialog()

