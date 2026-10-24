#Requires -Version 5.1
# TailCraft - 마인크래프트 서버 GUI 런처 (Paper / Fabric / NeoForge / Forge / Arclight + Tailscale / 포트포워딩)
# Copyright (c) 2026 Sangdeok. All rights reserved. 수정·재배포·복제 금지 — LICENSE.txt 참조.
param([string]$Root)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:TcRoot = if ($Root) { $Root } else { $script:AppDir }

# --- 무결성 검증: 번들된 core.ps1 이 공식 배포본과 다르면 실행 거부 ---
$script:CoreHash = '47B878B89419BA0CCF5446733EAE172A3494B639ACFE18E5485082FA8529404F'
if ($script:CoreHash -notmatch '^__') {
    try {
        $cp = Join-Path $script:AppDir 'lib\core.ps1'
        $h = (Get-FileHash -LiteralPath $cp -Algorithm SHA256).Hash
        if ($h -ne $script:CoreHash) {
            Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
            [System.Windows.MessageBox]::Show("core.ps1 이 공식 배포본과 일치하지 않습니다 (변조 또는 손상).`n공식 배포본을 다시 받으세요.`n`nExpected: $($script:CoreHash)`nActual:   $h", 'TailCraft - 무결성 오류', 'OK', 'Error') | Out-Null
            exit
        }
    } catch {}
}
. (Join-Path $script:AppDir 'lib\core.ps1')

$script:Cfg = Get-Config
$script:Proc = $null
$script:ProcStart = $null
$script:LastCpuTime = [TimeSpan]::Zero
$script:LastCpuCheck = Get-Date
$script:Players = New-Object System.Collections.Generic.List[string]
$script:ServerState = 'Stopped'   # Stopped | Starting | Running | Stopping
$script:BgTasks = New-Object System.Collections.ArrayList
$script:LogQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:SysInfo = Get-SystemInfo
$script:TutStep = -1
$script:NeedRestart = $false
$script:LogLines = 0
$script:Readers = @()
$script:UpnpPort = 0
$script:LanCache = $null
$script:LicenseVersion = '1.0'
$script:PlayerDb = @{}
$script:PlayerGridRefreshAt = $null

# ============================================================ XAML
[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TailCraft - 마인크래프트 서버 런처" Width="1040" Height="720" MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#1E1F26" FontFamily="Malgun Gothic" FontSize="13">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#2A2C36"/>
    <SolidColorBrush x:Key="Panel2" Color="#343745"/>
    <SolidColorBrush x:Key="Accent" Color="#4F9CF9"/>
    <SolidColorBrush x:Key="Text" Color="#E6E6E6"/>
    <SolidColorBrush x:Key="Muted" Color="#9AA0AE"/>
    <SolidColorBrush x:Key="Good" Color="#4CD964"/>
    <SolidColorBrush x:Key="Bad" Color="#FF5C5C"/>
    <SolidColorBrush x:Key="Warn" Color="#FFC24A"/>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="Margin" Value="0,4"/></Style>
    <Style TargetType="RadioButton"><Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="Margin" Value="0,4"/></Style>
    <Style TargetType="Label"><Setter Property="Foreground" Value="{StaticResource Muted}"/></Style>
    <Style TargetType="TextBox"><Setter Property="Background" Value="#1A1B22"/><Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="BorderBrush" Value="#444857"/><Setter Property="Padding" Value="6,4"/><Setter Property="CaretBrush" Value="White"/></Style>
    <Style TargetType="ComboBox"><Setter Property="Padding" Value="6,4"/><Setter Property="MinHeight" Value="28"/></Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Panel2}"/><Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="14,7"/><Setter Property="Margin" Value="4"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="Background" Value="{StaticResource Accent}"/><Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="Bold"/></Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="Background" Value="#B23B3B"/><Setter Property="Foreground" Value="White"/></Style>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="{StaticResource Panel}"/><Setter Property="CornerRadius" Value="10"/><Setter Property="Padding" Value="16"/><Setter Property="Margin" Value="6"/><Setter Property="BorderThickness" Value="2"/><Setter Property="BorderBrush" Value="Transparent"/></Style>
    <Style x:Key="H" TargetType="TextBlock" BasedOn="{StaticResource {x:Type TextBlock}}"><Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="Margin" Value="0,0,0,8"/></Style>
    <Style x:Key="Big" TargetType="TextBlock" BasedOn="{StaticResource {x:Type TextBlock}}"><Setter Property="FontSize" Value="26"/><Setter Property="FontWeight" Value="Bold"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock" BasedOn="{StaticResource {x:Type TextBlock}}"><Setter Property="Foreground" Value="{StaticResource Muted}"/><Setter Property="FontSize" Value="12"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="GridHeader" TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#2A2C36"/><Setter Property="Foreground" Value="#9AA0AE"/><Setter Property="Padding" Value="8,6"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="BorderThickness" Value="0"/></Style>
    <Style x:Key="GridCell" TargetType="DataGridCell"><Setter Property="Padding" Value="8,4"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DataGridCell"><Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}"><ContentPresenter VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value></Setter>
      <Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#2F5A9A"/><Setter Property="Foreground" Value="White"/></Trigger></Style.Triggers>
    </Style>
    <Style TargetType="ProgressBar"><Setter Property="Height" Value="10"/><Setter Property="Background" Value="#1A1B22"/><Setter Property="Foreground" Value="{StaticResource Accent}"/><Setter Property="BorderThickness" Value="0"/></Style>
    <Style TargetType="TabControl"><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="0"/></Style>
    <Style TargetType="TabItem">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="B" Background="Transparent" CornerRadius="8" Padding="18,9" Margin="2,0">
              <ContentPresenter ContentSource="Header" x:Name="CP"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="B" Property="Background" Value="{StaticResource Panel}"/><Setter Property="TextElement.Foreground" TargetName="CP" Value="White"/><Setter Property="TextElement.FontWeight" TargetName="CP" Value="Bold"/></Trigger>
              <Trigger Property="IsSelected" Value="False"><Setter Property="TextElement.Foreground" TargetName="CP" Value="{StaticResource Muted}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid Margin="12">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <!-- 상단 바 -->
      <DockPanel Grid.Row="0" Margin="4,0,4,8">
        <TextBlock Text="TailCraft" FontSize="20" FontWeight="Bold" Foreground="{StaticResource Accent}"/>
        <TextBlock x:Name="TopInfo" Margin="14,0,0,0" Style="{StaticResource Sub}" Text=""/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Ellipse x:Name="StateDot" Width="12" Height="12" Fill="{StaticResource Bad}" Margin="0,0,6,0"/>
          <TextBlock x:Name="StateText" Text="중지됨" FontWeight="Bold" Margin="0,0,16,0"/>
          <Button x:Name="BtnStart" Style="{StaticResource Primary}" Content="▶ 서버 시작"/>
          <Button x:Name="BtnStop" Style="{StaticResource Danger}" Content="■ 중지" IsEnabled="False"/>
          <Button x:Name="BtnRestart" Content="⟳ 재시작" IsEnabled="False"/>
        </StackPanel>
      </DockPanel>

      <TabControl x:Name="Tabs" Grid.Row="1">
        <!-- ================= 대시보드 ================= -->
        <TabItem Header="대시보드">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
          <Grid Margin="0,8,0,0">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Border Grid.Row="0" Style="{StaticResource Card}" x:Name="CardStatus">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel>
                  <TextBlock x:Name="DashTitle" Style="{StaticResource Big}" Text="서버가 설치되지 않았습니다"/>
                  <TextBlock x:Name="DashSub" Style="{StaticResource Sub}" Text="설정 탭에서 서버 종류와 버전을 고른 뒤 설치하세요."/>
                  <TextBlock x:Name="DashRestartHint" Foreground="{StaticResource Warn}" Text="⚠ 변경된 설정은 서버를 재시작해야 적용됩니다." Visibility="Collapsed" Margin="0,6,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <TextBlock Text="업타임" Style="{StaticResource Sub}" HorizontalAlignment="Right"/>
                  <TextBlock x:Name="DashUptime" Text="--:--:--" FontSize="22" FontWeight="Bold" HorizontalAlignment="Right"/>
                </StackPanel>
              </Grid>
            </Border>
            <UniformGrid Grid.Row="1" Columns="3">
              <Border Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock Text="CPU" Style="{StaticResource H}"/>
                  <TextBlock x:Name="CpuText" Style="{StaticResource Big}" Text="0 %"/>
                  <ProgressBar x:Name="CpuBar" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CpuSub" Style="{StaticResource Sub}" Text="논리 코어 사용 가능"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" x:Name="CardRam">
                <StackPanel>
                  <TextBlock Text="메모리 (RAM)" Style="{StaticResource H}"/>
                  <TextBlock x:Name="RamText" Style="{StaticResource Big}" Text="0 / 0 MB"/>
                  <ProgressBar x:Name="RamBar" Margin="0,8,0,4"/>
                  <TextBlock x:Name="RamSub" Style="{StaticResource Sub}" Text=""/>
                  <DockPanel Margin="0,10,0,0">
                    <TextBlock Text="할당" Style="{StaticResource Sub}" Margin="0,0,8,0"/>
                    <TextBlock x:Name="DashRamVal" DockPanel.Dock="Right" Text="4096 MB" FontWeight="Bold" Margin="8,0,0,0"/>
                    <Slider x:Name="DashRamSlider" Minimum="1024" Maximum="8192" TickFrequency="512" IsSnapToTickEnabled="True" VerticalAlignment="Center"/>
                  </DockPanel>
                  <Button x:Name="BtnDashRamApply" Content="할당량 적용" HorizontalAlignment="Right" Margin="0,6,0,0" Padding="10,4"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock Text="디스크" Style="{StaticResource H}"/>
                  <TextBlock x:Name="DiskText" Style="{StaticResource Big}" Text="0 MB"/>
                  <TextBlock Style="{StaticResource Sub}" Text="서버 폴더 전체 크기 (월드 포함)" Margin="0,8,0,4"/>
                  <TextBlock x:Name="DiskSub" Style="{StaticResource Sub}" Text=""/>
                  <Button x:Name="BtnOpenFolder" Content="서버 폴더 열기" HorizontalAlignment="Right" Margin="0,10,0,0" Padding="10,4"/>
                </StackPanel>
              </Border>
            </UniformGrid>
            <Grid Grid.Row="2">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border Style="{StaticResource Card}">
                <DockPanel>
                  <DockPanel DockPanel.Dock="Top">
                    <TextBlock Text="접속자" Style="{StaticResource H}"/>
                    <TextBlock x:Name="PlayerCount" Text="0 / 10" DockPanel.Dock="Right" FontWeight="Bold" Margin="12,0,0,8"/>
                  </DockPanel>
                  <ListBox x:Name="PlayerList" Background="#1A1B22" Foreground="{StaticResource Text}" BorderThickness="0" MinHeight="120"/>
                </DockPanel>
              </Border>
              <Border Grid.Column="1" Style="{StaticResource Card}" x:Name="CardAddr">
                <StackPanel>
                  <TextBlock Text="친구 접속 주소" Style="{StaticResource H}"/>
                  <TextBlock x:Name="AddrMode" Style="{StaticResource Sub}" Text=""/>
                  <TextBox x:Name="AddrBox" IsReadOnly="True" FontSize="18" FontWeight="Bold" Margin="0,8" Text="-"/>
                  <StackPanel Orientation="Horizontal">
                    <Button x:Name="BtnCopyAddr" Content="주소 복사"/>
                    <Button x:Name="BtnCopyInvite" Content="친구용 안내문 복사"/>
                  </StackPanel>
                  <TextBlock x:Name="AddrHint" Style="{StaticResource Sub}" Text=""/>
                </StackPanel>
              </Border>
            </Grid>
          </Grid>
          </ScrollViewer>
        </TabItem>

        <!-- ================= 설정 ================= -->
        <TabItem Header="설정">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="0,8,0,0">
            <Border Style="{StaticResource Card}" x:Name="CardSoftware">
              <StackPanel>
                <TextBlock Text="서버 소프트웨어" Style="{StaticResource H}"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Label Content="종류"/><ComboBox x:Name="CbLoader" Grid.Column="1" Margin="0,2,10,2">
                    <ComboBoxItem Tag="paper" Content="Paper (플러그인 / 바닐라 최적화)"/>
                    <ComboBoxItem Tag="fabric" Content="Fabric (경량 모드)"/>
                    <ComboBoxItem Tag="neoforge" Content="NeoForge (모드, 1.20.2+)"/>
                    <ComboBoxItem Tag="forge" Content="Forge (모드)"/>
                    <ComboBoxItem Tag="arclight-forge" Content="Arclight-Forge (모드 + 플러그인)"/>
                    <ComboBoxItem Tag="arclight-neoforge" Content="Arclight-NeoForge (모드 + 플러그인)"/>
                    <ComboBoxItem Tag="arclight-fabric" Content="Arclight-Fabric (모드 + 플러그인)"/>
                  </ComboBox>
                  <Label Grid.Column="2" Content="마인크래프트 버전"/><ComboBox x:Name="CbMc" Grid.Column="3" Margin="0,2,10,2"/>
                  <Label Grid.Column="4" Content="로더/빌드 버전"/><ComboBox x:Name="CbLv" Grid.Column="5" Margin="0,2,0,2"/>
                </Grid>
                <DockPanel Margin="0,10,0,0">
                  <TextBlock x:Name="InstallState" Style="{StaticResource Sub}" Text="설치되지 않음"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="BtnRefreshVersions" Content="버전 목록 새로고침"/>
                    <Button x:Name="BtnInstall" Style="{StaticResource Primary}" Content="설치 / 재설치"/>
                  </StackPanel>
                </DockPanel>
                <TextBlock Style="{StaticResource Sub}" Margin="0,6,0,0" Text="필요한 Java는 버전에 맞춰 자동으로 내려받아 runtime 폴더에 넣습니다. 재설치해도 월드·플러그인·모드 폴더는 유지됩니다. Arclight = Forge/NeoForge/Fabric 서버에서 Bukkit 플러그인(EssentialsX 등)까지 쓰는 하이브리드 서버 — 개발팀이 빌드한 마크 버전만 선택 가능(전체 버전은 순정 로더에서)."/>
                <CheckBox x:Name="CkAutoEss" Margin="0,6,0,0" Content="설치 시 기본 세트 자동 설치 — Paper/Arclight: EssentialsX · Fabric 계열: Fabric API"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" x:Name="CardRes">
              <StackPanel>
                <TextBlock Text="자원 할당" Style="{StaticResource H}"/>
                <DockPanel>
                  <TextBlock Text="메모리(RAM)" Width="120"/>
                  <TextBlock x:Name="RamVal" DockPanel.Dock="Right" Width="90" TextAlignment="Right" FontWeight="Bold" Text="4096 MB"/>
                  <Slider x:Name="RamSlider" Minimum="1024" Maximum="8192" TickFrequency="512" IsSnapToTickEnabled="True" TickPlacement="BottomRight" VerticalAlignment="Center"/>
                </DockPanel>
                <TextBlock x:Name="RamAdvice" Style="{StaticResource Sub}" Text=""/>
                <DockPanel Margin="0,10,0,0">
                  <TextBlock Text="추가 JVM 인수" Width="120"/>
                  <TextBox x:Name="TbJvm" ToolTip="예: -XX:+UseZGC  (비워도 됨. 기본으로 Aikar 플래그 적용)"/>
                </DockPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" x:Name="CardGame">
              <StackPanel>
                <TextBlock Text="게임 설정 (server.properties)" Style="{StaticResource H}"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                  <Label Content="포트"/><TextBox x:Name="TbPort" Grid.Column="1" Margin="0,3,10,3"/>
                  <Label Grid.Column="2" Content="최대 인원"/><TextBox x:Name="TbMax" Grid.Column="3" Margin="0,3,10,3"/>
                  <Label Grid.Column="4" Content="시야 거리"/><TextBox x:Name="TbView" Grid.Column="5" Margin="0,3,0,3"/>
                  <Label Grid.Row="1" Content="난이도"/><ComboBox x:Name="CbDiff" Grid.Row="1" Grid.Column="1" Margin="0,3,10,3"><ComboBoxItem Content="peaceful"/><ComboBoxItem Content="easy"/><ComboBoxItem Content="normal"/><ComboBoxItem Content="hard"/></ComboBox>
                  <Label Grid.Row="1" Grid.Column="2" Content="게임 모드"/><ComboBox x:Name="CbMode" Grid.Row="1" Grid.Column="3" Margin="0,3,10,3"><ComboBoxItem Content="survival"/><ComboBoxItem Content="creative"/><ComboBoxItem Content="adventure"/><ComboBoxItem Content="spectator"/></ComboBox>
                  <Label Grid.Row="1" Grid.Column="4" Content="MOTD"/><TextBox x:Name="TbMotd" Grid.Row="1" Grid.Column="5" Margin="0,3,0,3"/>
                  <CheckBox x:Name="CkOnline" Grid.Row="2" Grid.ColumnSpan="2" Content="정품 인증 (online-mode) — 끄면 비정품도 접속 가능하지만 사칭 위험 있음"/>
                  <CheckBox x:Name="CkWhitelist" Grid.Row="2" Grid.Column="2" Grid.ColumnSpan="4" Content="화이트리스트 사용 (콘솔에서 whitelist add 닉네임)"/>
                </Grid>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" x:Name="CardEula">
              <StackPanel>
                <CheckBox x:Name="CkEula" Content="Minecraft EULA(최종 사용자 라이선스)를 읽었고 동의합니다."/>
                <TextBlock Style="{StaticResource Sub}"><Hyperlink x:Name="LinkEula" NavigateUri="https://aka.ms/MinecraftEULA" Foreground="#4F9CF9">https://aka.ms/MinecraftEULA</Hyperlink> — 동의하지 않으면 서버를 실행할 수 없습니다.</TextBlock>
                <CheckBox x:Name="CkAutoStart" Content="런처를 열면 서버를 자동으로 시작"/>
              </StackPanel>
            </Border>
            <Button x:Name="BtnSaveSettings" Style="{StaticResource Primary}" Content="설정 저장" HorizontalAlignment="Right" Width="160"/>
          </StackPanel>
          </ScrollViewer>
        </TabItem>

        <!-- ================= 네트워크 ================= -->
        <TabItem Header="네트워크">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="0,8,0,0">
            <Border Style="{StaticResource Card}" x:Name="CardNetMode">
              <StackPanel>
                <TextBlock Text="친구가 접속하는 방식" Style="{StaticResource H}"/>
                <RadioButton x:Name="RbTailscale" GroupName="net" Content="테일스케일 (추천) — 포트포워딩 없이, 친구도 Tailscale 앱 설치 후 접속"/>
                <TextBlock Style="{StaticResource Sub}" Margin="22,0,0,6" Text="공유기 설정 불필요. 암호화된 P2P 연결. 친구는 자기 계정으로 로그인하고, 내가 만든 '공유 링크'를 열어 Accept 하면 친구 기기 목록에 내 서버 PC가 추가됩니다(노드 공유). 친구 수 제한 없음."/>
                <RadioButton x:Name="RbPortfwd" GroupName="net" Content="포트포워딩 — 공유기에서 포트를 열고 공인 IP로 접속 (친구는 아무것도 설치 안 함)"/>
                <TextBlock Style="{StaticResource Sub}" Margin="22,0,0,6" Text="공유기 UPnP가 켜져 있으면 자동 개방 시도. 아니면 설명서(PDF)의 수동 절차를 따르세요. 공인 IP가 바뀌면 친구에게 다시 알려야 합니다."/>
                <RadioButton x:Name="RbLan" GroupName="net" Content="LAN 전용 — 같은 공유기(집/PC방) 안에서만 접속"/>
              </StackPanel>
            </Border>

            <!-- Tailscale -->
            <Border Style="{StaticResource Card}" x:Name="PanelTs">
              <StackPanel>
                <DockPanel>
                  <TextBlock Text="테일스케일" Style="{StaticResource H}"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Ellipse x:Name="TsDot" Width="10" Height="10" Fill="{StaticResource Bad}" Margin="0,0,6,8"/>
                    <TextBlock x:Name="TsState" Text="확인 중..." Margin="0,0,0,8"/>
                  </StackPanel>
                </DockPanel>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                  <Label Content="Tailscale IP"/><TextBox x:Name="TsIp" Grid.Column="1" IsReadOnly="True" Margin="0,3"/><Button x:Name="BtnCopyTsIp" Grid.Column="2" Content="복사" Padding="10,4"/>
                  <Label Grid.Row="1" Content="MagicDNS 이름"/><TextBox x:Name="TsDns" Grid.Row="1" Grid.Column="1" IsReadOnly="True" Margin="0,3"/><Button x:Name="BtnCopyTsDns" Grid.Row="1" Grid.Column="2" Content="복사" Padding="10,4"/>
                  <Label Grid.Row="2" Content="로그인 계정"/><TextBlock x:Name="TsUser" Grid.Row="2" Grid.Column="1" Text="-"/>
                </Grid>
                <Border Background="#1A1B22" CornerRadius="8" Padding="12" Margin="0,10,0,0">
                  <StackPanel>
                    <TextBlock FontWeight="Bold" Text="친구 초대 = 노드 공유 (3단계)"/>
                    <TextBlock Style="{StaticResource Sub}" Text="① [관리 콘솔 열기] → 서버 PC 행의 ··· → Share… → 'Copy invite link' 탭 → Reusable link 켜기 → Copy share link&#x0a;② 복사한 링크를 아래 칸에 붙여넣고 [설정 저장] → 대시보드의 '친구용 안내문 복사'에 링크가 자동 포함됩니다&#x0a;③ 친구: Tailscale 설치 → 아무 계정으로 로그인 → 링크 열어 Accept → 기기 목록에 내 서버 PC가 뜨면 아래 Tailscale IP로 접속"/>
                    <DockPanel Margin="0,8,0,0">
                      <Label Content="공유 링크" Width="80"/>
                      <TextBox x:Name="TsShareLink" ToolTip="https://login.tailscale.com/admin/invite/... 형태"/>
                    </DockPanel>
                    <TextBlock Style="{StaticResource Sub}" Text="링크는 비밀번호처럼 취급 (가진 사람은 누구나 서버 PC 접근 가능). 잘못 퍼지면 관리 콘솔 → Share → Revoke invite."/>
                  </StackPanel>
                </Border>
                <WrapPanel Margin="0,8,0,0">
                  <Button x:Name="BtnTsInstall" Style="{StaticResource Primary}" Content="1. 테일스케일 설치"/>
                  <Button x:Name="BtnTsLogin" Style="{StaticResource Primary}" Content="2. 로그인 / 연결"/>
                  <Button x:Name="BtnTsAdmin" Content="관리 콘솔 열기 (기기 공유)"/>
                  <Button x:Name="BtnTsRefresh" Content="상태 새로고침"/>
                </WrapPanel>
                <TextBlock Text="연결된 기기 (친구가 Tailscale에 들어오면 여기 보입니다)" Style="{StaticResource Sub}" Margin="0,10,0,4"/>
                <ListBox x:Name="TsPeers" Background="#1A1B22" Foreground="{StaticResource Text}" BorderThickness="0" MinHeight="70" MaxHeight="140"/>
              </StackPanel>
            </Border>

            <!-- 포트포워딩 -->
            <Border Style="{StaticResource Card}" x:Name="PanelPf">
              <StackPanel>
                <TextBlock Text="포트포워딩" Style="{StaticResource H}"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                  <Label Content="공인 IP"/><TextBox x:Name="PfPublic" Grid.Column="1" IsReadOnly="True" Margin="0,3"/><Button x:Name="BtnPfPublic" Grid.Column="2" Content="조회" Padding="10,4"/>
                  <Label Grid.Row="1" Content="이 PC 내부 IP"/><TextBox x:Name="PfLocal" Grid.Row="1" Grid.Column="1" IsReadOnly="True" Margin="0,3"/>
                  <Label Grid.Row="2" Content="공유기 주소"/><TextBox x:Name="PfGw" Grid.Row="2" Grid.Column="1" IsReadOnly="True" Margin="0,3"/><Button x:Name="BtnPfGw" Grid.Row="2" Grid.Column="2" Content="관리 페이지 열기" Padding="10,4"/>
                </Grid>
                <DockPanel Margin="0,8,0,0">
                  <CheckBox x:Name="CkUpnp" Content="UPnP로 포트 자동 개방 (서버 시작 시)"/>
                  <TextBlock x:Name="UpnpState" DockPanel.Dock="Right" Style="{StaticResource Sub}" Text=""/>
                </DockPanel>
                <WrapPanel>
                  <Button x:Name="BtnUpnpNow" Style="{StaticResource Primary}" Content="지금 UPnP 개방 시도"/>
                  <Button x:Name="BtnPortCheck" Content="외부에서 포트 열림 확인 (서버 켠 뒤)"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Sub}" Text="UPnP가 실패하면 공유기 관리 페이지 → 포트포워딩(NAT) 메뉴에서 '외부 포트 = 내부 포트 = 위 포트번호, 내부 IP = 이 PC 내부 IP, TCP'로 직접 추가하세요. 자세한 화면별 절차는 PDF 설명서 4장."/>
              </StackPanel>
            </Border>

            <!-- LAN -->
            <Border Style="{StaticResource Card}" x:Name="PanelLan">
              <StackPanel>
                <TextBlock Text="LAN" Style="{StaticResource H}"/>
                <TextBlock Style="{StaticResource Sub}" Text="같은 공유기에 연결된 친구는 아래 주소로 바로 접속합니다. 방화벽 규칙만 추가하면 됩니다."/>
                <TextBox x:Name="LanAddr" IsReadOnly="True" FontSize="16" FontWeight="Bold" Margin="0,8"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" x:Name="CardFw">
              <StackPanel>
                <TextBlock Text="Windows 방화벽" Style="{StaticResource H}"/>
                <DockPanel>
                  <TextBlock x:Name="FwState" Style="{StaticResource Sub}" Text="확인 중..."/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="BtnFw" Style="{StaticResource Primary}" Content="방화벽 허용 규칙 추가 (관리자 권한)"/>
                    <Button x:Name="BtnOpenPdf" Content="📄 네트워크 설정 설명서(PDF)"/>
                  </StackPanel>
                </DockPanel>
                <TextBlock Style="{StaticResource Sub}" Text="어떤 모드든 서버 포트(TCP)를 들어오는 연결에 허용해야 친구가 접속할 수 있습니다. 한 번만 하면 됩니다."/>
              </StackPanel>
            </Border>
          </StackPanel>
          </ScrollViewer>
        </TabItem>

        <!-- ================= 모드/플러그인 ================= -->
        <TabItem Header="모드/플러그인">
          <Grid Margin="0,8,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
            <Grid>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <Border Style="{StaticResource Card}" x:Name="CardMods">
                <DockPanel>
                  <StackPanel>
                    <TextBlock Text="설치된 목록" Style="{StaticResource H}"/>
                    <TextBlock x:Name="ModsHint" Style="{StaticResource Sub}" Text=""/>
                  </StackPanel>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
                    <RadioButton x:Name="RbKindMod" GroupName="kind" Content="mods" IsChecked="True" Margin="6,0"/>
                    <RadioButton x:Name="RbKindPlugin" GroupName="kind" Content="plugins" Margin="6,0"/>
                  </StackPanel>
                </DockPanel>
              </Border>
              <DataGrid x:Name="ModGrid" Grid.Row="1" Margin="6,0" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" SelectionMode="Single" HeadersVisibility="Column"
                        Background="#1A1B22" Foreground="{StaticResource Text}" RowBackground="#1A1B22" AlternatingRowBackground="#22242D" BorderThickness="0" GridLinesVisibility="None" FontSize="12.5"
                        ColumnHeaderStyle="{StaticResource GridHeader}" CellStyle="{StaticResource GridCell}">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="사용" Binding="{Binding Enabled}" Width="45"/>
                  <DataGridTextColumn Header="이름" Binding="{Binding Name}" Width="170"/>
                  <DataGridTextColumn Header="버전" Binding="{Binding Version}" Width="110"/>
                  <DataGridTextColumn Header="종류" Binding="{Binding Type}" Width="100"/>
                  <DataGridTextColumn Header="파일" Binding="{Binding File}" Width="*"/>
                  <DataGridTextColumn Header="MB" Binding="{Binding SizeMB}" Width="55"/>
                </DataGrid.Columns>
              </DataGrid>
              <Border Grid.Row="2" Style="{StaticResource Card}">
                <WrapPanel>
                  <Button x:Name="BtnModToggle" Style="{StaticResource Primary}" Content="사용 / 사용 안 함"/>
                  <Button x:Name="BtnModAdd" Content="＋ 파일 추가"/>
                  <Button x:Name="BtnModDelete" Style="{StaticResource Danger}" Content="삭제"/>
                  <Button x:Name="BtnModFolder" Content="폴더 열기"/>
                  <Button x:Name="BtnModRefresh" Content="새로고침"/>
                  <Button x:Name="BtnModExport" Content="📦 친구용 모드 zip 내보내기"/>
                </WrapPanel>
              </Border>
            </Grid>
            <Grid Grid.Column="1">
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <Border Style="{StaticResource Card}" x:Name="CardRecommend">
                <StackPanel>
                  <TextBlock Text="추천 세트" Style="{StaticResource H}"/>
                  <StackPanel x:Name="RecPanel"/>
                  <Button x:Name="BtnRecInstall" Style="{StaticResource Primary}" Content="선택 항목 설치" HorizontalAlignment="Right"/>
                </StackPanel>
              </Border>
              <Border Grid.Row="1" Style="{StaticResource Card}">
                <DockPanel>
                  <TextBlock DockPanel.Dock="Top" Text="Modrinth 검색·설치" Style="{StaticResource H}"/>
                  <DockPanel DockPanel.Dock="Top">
                    <Button x:Name="BtnMrSearch" DockPanel.Dock="Right" Content="검색" Padding="10,4"/>
                    <TextBox x:Name="MrQuery" ToolTip="예: worldedit, sodium, essentials"/>
                  </DockPanel>
                  <DockPanel DockPanel.Dock="Bottom" Margin="0,6,0,0">
                    <Button x:Name="BtnMrInstall" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="선택 설치 (의존성 포함)"/>
                    <TextBlock x:Name="MrInfo" Style="{StaticResource Sub}" Text="현재 서버 버전·로더에 맞는 것만 검색됩니다."/>
                  </DockPanel>
                  <ListBox x:Name="MrList" Margin="0,6,0,0" Background="#1A1B22" Foreground="{StaticResource Text}" BorderThickness="0"/>
                </DockPanel>
              </Border>
            </Grid>
          </Grid>
        </TabItem>

        <!-- ================= 플레이어 ================= -->
        <TabItem Header="플레이어">
          <Grid Margin="0,8,0,0">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Border Style="{StaticResource Card}" x:Name="CardPlayers">
              <StackPanel>
                <TextBlock Text="접속 기록과 권한 관리" Style="{StaticResource H}"/>
                <TextBlock Style="{StaticResource Sub}" Text="서버에 접속한 모든 플레이어가 기록됩니다. 행을 선택하고 아래 버튼을 누르면 콘솔 명령이 자동으로 전송됩니다 (서버 실행 중일 때). MAC 주소는 같은 공유기(LAN)에서 접속한 경우에만 표시되며, 테일스케일/인터넷 접속자는 원리상 알 수 없습니다 — 대신 테일스케일 기기 이름이 표시됩니다."/>
              </StackPanel>
            </Border>
            <DataGrid x:Name="PlayerGrid" Grid.Row="1" Margin="6,0" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" SelectionMode="Single" HeadersVisibility="Column"
                      Background="#1A1B22" Foreground="{StaticResource Text}" RowBackground="#1A1B22" AlternatingRowBackground="#22242D" BorderThickness="0" GridLinesVisibility="None" FontSize="12.5"
                      ColumnHeaderStyle="{StaticResource GridHeader}" CellStyle="{StaticResource GridCell}">
              <DataGrid.Columns>
                <DataGridTextColumn Header="상태" Binding="{Binding Status}" Width="60"/>
                <DataGridTextColumn Header="닉네임" Binding="{Binding Name}" Width="140"/>
                <DataGridTextColumn Header="IP 주소" Binding="{Binding IP}" Width="130"/>
                <DataGridTextColumn Header="MAC (LAN만)" Binding="{Binding MAC}" Width="140"/>
                <DataGridTextColumn Header="Tailscale 기기" Binding="{Binding Device}" Width="150"/>
                <DataGridTextColumn Header="화이트리스트" Binding="{Binding WL}" Width="90"/>
                <DataGridTextColumn Header="OP" Binding="{Binding OP}" Width="50"/>
                <DataGridTextColumn Header="최근 접속" Binding="{Binding LastSeen}" Width="130"/>
                <DataGridTextColumn Header="접속 횟수" Binding="{Binding Count}" Width="70"/>
                <DataGridTextColumn Header="UUID" Binding="{Binding UUID}" Width="*"/>
              </DataGrid.Columns>
            </DataGrid>
            <Border Grid.Row="2" Style="{StaticResource Card}">
              <DockPanel>
                <TextBlock x:Name="PlayerSelInfo" Style="{StaticResource Sub}" Text="행을 선택하세요"/>
                <WrapPanel HorizontalAlignment="Right">
                  <Button x:Name="BtnWlAdd" Style="{StaticResource Primary}" Content="✔ 화이트리스트 추가"/>
                  <Button x:Name="BtnWlRemove" Content="화이트리스트 제거"/>
                  <Button x:Name="BtnOpAdd" Content="OP 부여"/>
                  <Button x:Name="BtnOpRemove" Content="OP 해제"/>
                  <Button x:Name="BtnKick" Content="킥"/>
                  <Button x:Name="BtnBan" Style="{StaticResource Danger}" Content="밴"/>
                  <Button x:Name="BtnBanIp" Style="{StaticResource Danger}" Content="IP 밴"/>
                  <Button x:Name="BtnPardon" Content="밴 해제"/>
                  <Button x:Name="BtnWlToggle" Content="화이트리스트 켜기/끄기"/>
                  <Button x:Name="BtnPlayersRefresh" Content="새로고침"/>
                </WrapPanel>
              </DockPanel>
            </Border>
          </Grid>
        </TabItem>

        <!-- ================= 콘솔 ================= -->
        <TabItem Header="콘솔">
          <Grid Margin="0,8,0,0">
            <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBox x:Name="ConsoleBox" IsReadOnly="True" FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" AcceptsReturn="True" Background="#121318"/>
            <WrapPanel Grid.Row="1" Margin="0,6,0,0" x:Name="QuickCmdPanel"/>
            <DockPanel Grid.Row="2" Margin="0,6,0,0">
              <Button x:Name="BtnSend" DockPanel.Dock="Right" Content="보내기" Style="{StaticResource Primary}"/>
              <Button x:Name="BtnCmdSave" DockPanel.Dock="Right" Content="★ 즐겨찾기" ToolTip="입력한 명령을 빠른 버튼으로 저장 (우클릭으로 삭제)"/>
              <Button x:Name="BtnClearLog" DockPanel.Dock="Right" Content="지우기"/>
              <TextBox x:Name="CmdBox" FontFamily="Consolas" ToolTip="예: op 닉네임 / whitelist add 닉네임 / say 안녕 / list"/>
            </DockPanel>
          </Grid>
        </TabItem>

        <!-- ================= 도움말 ================= -->
        <TabItem Header="도움말">
          <StackPanel Margin="0,8,0,0">
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="처음이신가요?" Style="{StaticResource H}"/>
                <TextBlock Style="{StaticResource Sub}" Text="튜토리얼은 화면 아래에 안내 배너로 진행되며, 실제 버튼을 직접 눌러가며 서버를 완성합니다."/>
                <WrapPanel Margin="0,8,0,0">
                  <Button x:Name="BtnTutorial" Style="{StaticResource Primary}" Content="▶ 튜토리얼 다시 보기"/>
                  <Button x:Name="BtnOpenPdf2" Content="📄 네트워크 설정 설명서 (PDF)"/>
                  <Button x:Name="BtnOpenRoot" Content="런처 폴더 열기"/>
                  <Button x:Name="BtnLicense" Content="📜 라이선스 보기"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Sub}" Margin="0,8,0,0" Text="TailCraft © 2026 Sangdeok. All rights reserved. 수정·재배포·복제 금지 — 자세한 내용은 LICENSE.txt.&#x0a;문의: dwxw777@gmail.com · Discord sangdeok (https://discord.gg/rv5sH6RbS) · Mojang/Microsoft/Tailscale과 무관한 비공식 도구입니다."/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="진단 / 디버깅" Style="{StaticResource H}"/>
                <TextBlock Style="{StaticResource Sub}" Text="문제가 생기면 [진단 실행]을 눌러 결과를 복사해 질문에 붙여넣으세요. Java·포트 점유·방화벽·테일스케일·UPnP·디스크·설정·최근 로그가 한 번에 정리됩니다."/>
                <WrapPanel Margin="0,8,0,0">
                  <Button x:Name="BtnDiag" Style="{StaticResource Primary}" Content="🩺 진단 실행 → 결과 복사"/>
                  <Button x:Name="BtnOpenLogs" Content="서버 logs 폴더"/>
                  <Button x:Name="BtnOpenLatestLog" Content="latest.log 열기"/>
                  <Button x:Name="BtnOpenCrash" Content="크래시 리포트 폴더"/>
                  <Button x:Name="BtnOpenTcLog" Content="런처 로그(tailcraft.log)"/>
                  <Button x:Name="BtnCopyConsole" Content="콘솔 최근 200줄 복사"/>
                </WrapPanel>
                <TextBox x:Name="DiagBox" IsReadOnly="True" FontFamily="Consolas" FontSize="11.5" Height="160" Margin="0,8,0,0" VerticalScrollBarVisibility="Auto" TextWrapping="NoWrap" HorizontalScrollBarVisibility="Auto" Visibility="Collapsed"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="폴더 구조" Style="{StaticResource H}"/>
                <TextBlock Style="{StaticResource Sub}" Text="server\  — 서버 본체. world(월드), plugins(Paper 플러그인), mods(Fabric/Forge 모드), server.properties&#x0a;runtime\ — 자동 설치된 Java&#x0a;docs\ — 설명서&#x0a;config.json — 런처 설정"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="자주 묻는 문제" Style="{StaticResource H}"/>
                <TextBlock Style="{StaticResource Sub}" Text="• 친구가 접속 못함 → 네트워크 탭 방화벽 규칙 추가 → 테일스케일이면 친구 PC도 Tailscale '연결됨' 상태인지 → 포트포워딩이면 '외부 포트 확인' 사이트에서 Open인지 확인&#x0a;• 서버가 바로 꺼짐 → 콘솔 탭 마지막 줄 확인. EULA 미동의, 메모리 과다 할당, 포트 충돌이 대부분&#x0a;• 렉 → 메모리 할당을 늘리거나 시야 거리를 8 이하로&#x0a;• 모드 서버 → server\mods 에 모드 jar를 넣고 재시작. 친구도 같은 모드 필요"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </TabItem>
      </TabControl>
    </Grid>

    <!-- 튜토리얼 배너 -->
    <Border x:Name="TutBanner" Visibility="Collapsed" VerticalAlignment="Bottom" Margin="24,0,24,20" Background="#F0252A3A" BorderBrush="{StaticResource Accent}" BorderThickness="2" CornerRadius="12" Padding="18,14">
      <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="TutStepText" Style="{StaticResource Sub}" Text="튜토리얼 1 / 8"/>
          <TextBlock x:Name="TutTitle" FontSize="17" FontWeight="Bold" Margin="0,2,0,4" Text=""/>
          <TextBlock x:Name="TutBody" TextWrapping="Wrap" Text="" MaxWidth="760" HorizontalAlignment="Left"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnTutSkip" Content="건너뛰기"/>
          <Button x:Name="BtnTutPrev" Content="◀ 이전"/>
          <Button x:Name="BtnTutNext" Style="{StaticResource Primary}" Content="다음 ▶"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- 작업 중 오버레이 -->
    <Grid x:Name="Busy" Visibility="Collapsed" Background="#CC14151B">
      <Border Background="{StaticResource Panel}" CornerRadius="12" Padding="30" HorizontalAlignment="Center" VerticalAlignment="Center" MinWidth="420">
        <StackPanel>
          <TextBlock x:Name="BusyTitle" FontSize="16" FontWeight="Bold" Text="작업 중"/>
          <TextBlock x:Name="BusyText" Style="{StaticResource Sub}" Margin="0,8,0,12" Text=""/>
          <ProgressBar IsIndeterminate="True"/>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$W = [Windows.Markup.XamlReader]::Load($reader)
$Xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    if ($n) { Set-Variable -Name $n -Value $W.FindName($n) -Scope Script }
}

# ============================================================ 유틸
function Set-Busy($title, $text) {
    if ($title) { $BusyTitle.Text = $title; $BusyText.Text = $text; $Busy.Visibility = 'Visible' }
    else { $Busy.Visibility = 'Collapsed' }
}
function Show-Msg($text, $title = 'TailCraft', $icon = 'Information') {
    [System.Windows.MessageBox]::Show($W, $text, $title, 'OK', $icon) | Out-Null
}
function Ask-YesNo($text, $title = 'TailCraft') {
    return ([System.Windows.MessageBox]::Show($W, $text, $title, 'YesNo', 'Question') -eq 'Yes')
}
function Write-TcLog($line) { try { Add-Content -Path (Join-Path $global:TcRoot 'tailcraft.log') -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $line" -Encoding UTF8 } catch {} }
function Append-Log($line) {
    if ($line -like '`[TailCraft`]*' -or $line -match 'ERROR|Exception|FATAL') { Write-TcLog $line }
    $ConsoleBox.AppendText($line + "`r`n")
    $script:LogLines++
    if ($script:LogLines -gt 3000) {
        $ConsoleBox.Text = (($ConsoleBox.Text -split "`r`n") | Select-Object -Last 1500) -join "`r`n"
        $script:LogLines = 1500
    }
    $ConsoleBox.ScrollToEnd()
}
function Get-SelectedTag($cb) { if ($cb.SelectedItem) { return $cb.SelectedItem.Tag } return $null }
function Select-ByTag($cb, $tag) { foreach ($i in $cb.Items) { if ($i.Tag -eq $tag) { $cb.SelectedItem = $i; return } } }
function Select-ByContent($cb, $c) { foreach ($i in $cb.Items) { if ("$($i.Content)" -eq "$c") { $cb.SelectedItem = $i; return } } }
function Set-Clip($t) { try { [System.Windows.Clipboard]::SetText("$t") } catch { Show-Msg '클립보드를 사용할 수 없습니다. 다시 시도하세요.' } }

# 백그라운드 작업: $Work 는 $P(파라미터 해시)와 $Status(스크립트블록)를 쓸 수 있음
function Start-BgTask($title, $text, [hashtable]$P, [scriptblock]$Work, [scriptblock]$OnDone) {
    $Sync = [hashtable]::Synchronized(@{ Status = $text; Done = $false; Error = $null; Result = $null })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $Sync)
    $rs.SessionStateProxy.SetVariable('P', $P)
    $rs.SessionStateProxy.SetVariable('TcRootPath', $global:TcRoot)
    $rs.SessionStateProxy.SetVariable('AppDirPath', $script:AppDir)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $code = @"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$global:TcRoot = `$TcRootPath
. (Join-Path `$AppDirPath 'lib\core.ps1')
`$Status = { param(`$m) `$Sync.Status = `$m }
try { `$Sync.Result = & { $($Work.ToString()) } } catch { `$Sync.Error = `$_.Exception.Message }
`$Sync.Done = `$true
"@
    $ps.AddScript($code) | Out-Null
    $handle = $ps.BeginInvoke()
    [void]$script:BgTasks.Add(@{ Sync = $Sync; PS = $ps; RS = $rs; Handle = $handle; OnDone = $OnDone; Title = $title })
    Set-Busy $title $text
}

# ============================================================ 설정 <-> UI
function Load-SettingsToUi {
    $c = $script:Cfg
    Select-ByTag $CbLoader $c.loader
    $max = [math]::Max(2048, [math]::Floor(($script:SysInfo.TotalRamMB - 1536) / 512) * 512)
    $RamSlider.Maximum = $max; $DashRamSlider.Maximum = $max
    $RamSlider.Value = [math]::Min([int]$c.ramMB, $max); $DashRamSlider.Value = $RamSlider.Value
    $TbJvm.Text = $c.extraJvmArgs
    $TbPort.Text = "$($c.port)"; $TbMax.Text = "$($c.maxPlayers)"; $TbView.Text = "$($c.viewDistance)"; $TbMotd.Text = $c.motd
    Select-ByContent $CbDiff $c.difficulty; Select-ByContent $CbMode $c.gamemode
    $CkOnline.IsChecked = [bool]$c.onlineMode; $CkWhitelist.IsChecked = [bool]$c.whitelist
    $CkEula.IsChecked = [bool]$c.eulaAccepted; $CkAutoStart.IsChecked = [bool]$c.autoStart
    $CkUpnp.IsChecked = [bool]$c.upnp
    $TsShareLink.Text = "$($c.tsShareLink)"
    $CkAutoEss.IsChecked = [bool]$c.autoEssentials
    switch ($c.networkMode) { 'portforward' { $RbPortfwd.IsChecked = $true } 'lan' { $RbLan.IsChecked = $true } default { $RbTailscale.IsChecked = $true } }
    if ($c.mcVersion) { $CbMc.Items.Clear(); [void]$CbMc.Items.Add($c.mcVersion); $CbMc.SelectedIndex = 0 }
    if ($c.loaderVersion) { $CbLv.Items.Clear(); [void]$CbLv.Items.Add($c.loaderVersion); $CbLv.SelectedIndex = 0 }
    Update-InstallState
    Update-NetPanels
}

function Read-SettingsFromUi {
    $c = $script:Cfg
    $c.loader = Get-SelectedTag $CbLoader
    if ($CbMc.SelectedItem) { $c.mcVersion = "$($CbMc.SelectedItem)" }
    if ($CbLv.SelectedItem) { $c.loaderVersion = "$($CbLv.SelectedItem)" }
    $c.ramMB = [int]$RamSlider.Value
    $c.extraJvmArgs = $TbJvm.Text.Trim()
    $c.port = [int]$TbPort.Text; $c.maxPlayers = [int]$TbMax.Text; $c.viewDistance = [int]$TbView.Text; $c.motd = $TbMotd.Text
    $c.difficulty = "$($CbDiff.SelectedItem.Content)"; $c.gamemode = "$($CbMode.SelectedItem.Content)"
    $c.onlineMode = [bool]$CkOnline.IsChecked; $c.whitelist = [bool]$CkWhitelist.IsChecked
    $c.eulaAccepted = [bool]$CkEula.IsChecked; $c.autoStart = [bool]$CkAutoStart.IsChecked
    $c.upnp = [bool]$CkUpnp.IsChecked
    $c.tsShareLink = $TsShareLink.Text.Trim()
    $c.autoEssentials = [bool]$CkAutoEss.IsChecked
    $c.networkMode = if ($RbPortfwd.IsChecked) { 'portforward' } elseif ($RbLan.IsChecked) { 'lan' } else { 'tailscale' }
}

function Save-Settings {
    try { Read-SettingsFromUi } catch { Show-Msg "입력값을 확인하세요: $($_.Exception.Message)" 'TailCraft' 'Warning'; return }
    Save-Config $script:Cfg
    Write-ServerProperties $script:Cfg
    if ($script:Cfg.eulaAccepted) { Write-Eula }
    if ($script:ServerState -ne 'Stopped') { $script:NeedRestart = $true }
    Update-Dashboard
    Update-NetPanels
    try { Refresh-ModGrid; Refresh-RecPanel } catch {}
}

function Get-InstalledKey { return "$($script:Cfg.loader)-$($script:Cfg.mcVersion)-$($script:Cfg.loaderVersion)" }
function Test-Installed { return ($script:Cfg.installedKey -and ($script:Cfg.installedKey -eq (Get-InstalledKey))) }

function Update-InstallState {
    if (Test-Installed) {
        $InstallState.Text = "✔ 설치됨: $($script:Cfg.loader) $($script:Cfg.mcVersion) ($($script:Cfg.loaderVersion))"
        $InstallState.Foreground = $W.FindResource('Good')
    } elseif ($script:Cfg.installedKey) {
        $InstallState.Text = "현재 설치: $($script:Cfg.installedKey) — 선택한 버전과 다릅니다. '설치 / 재설치'를 누르세요."
        $InstallState.Foreground = $W.FindResource('Warn')
    } else {
        $InstallState.Text = '설치되지 않음'; $InstallState.Foreground = $W.FindResource('Muted')
    }
}

# ============================================================ 버전 목록
function Load-McVersions {
    $loader = Get-SelectedTag $CbLoader
    Start-BgTask '버전 목록 불러오는 중' "$loader 의 마인크래프트 버전 목록을 받는 중..." @{ loader = $loader } { Get-McVersions $P.loader } {
        param($S)
        if ($S.Error) { Show-Msg "버전 목록을 받지 못했습니다.`n$($S.Error)" 'TailCraft' 'Warning'; return }
        $cur = if ($CbMc.SelectedItem) { "$($CbMc.SelectedItem)" } else { $script:Cfg.mcVersion }
        $CbMc.Items.Clear()
        foreach ($v in $S.Result) { [void]$CbMc.Items.Add($v) }
        if ($cur -and $CbMc.Items.Contains($cur)) { $CbMc.SelectedItem = $cur } elseif ($CbMc.Items.Count -gt 0) { $CbMc.SelectedIndex = 0 }
    }
}
function Load-LoaderVersions {
    $loader = Get-SelectedTag $CbLoader
    $mc = if ($CbMc.SelectedItem) { "$($CbMc.SelectedItem)" } else { '' }
    if (-not $mc) { return }
    Start-BgTask '빌드 목록 불러오는 중' "$loader $mc 의 빌드 목록을 받는 중..." @{ loader = $loader; mc = $mc } { Get-LoaderVersions $P.loader $P.mc } {
        param($S)
        if ($S.Error) { Show-Msg "빌드 목록을 받지 못했습니다.`n$($S.Error)" 'TailCraft' 'Warning'; return }
        $cur = if ($CbLv.SelectedItem) { "$($CbLv.SelectedItem)" } else { $script:Cfg.loaderVersion }
        $CbLv.Items.Clear()
        foreach ($v in $S.Result) { [void]$CbLv.Items.Add($v) }
        if ($cur -and $CbLv.Items.Contains($cur)) { $CbLv.SelectedItem = $cur } elseif ($CbLv.Items.Count -gt 0) { $CbLv.SelectedIndex = 0 }
        Update-InstallState
    }
}

function Install-ServerUi {
    if (-not $CbMc.SelectedItem -or -not $CbLv.SelectedItem) { Show-Msg '마인크래프트 버전과 로더 버전을 먼저 선택하세요. (버전 목록 새로고침)' 'TailCraft' 'Warning'; return }
    if (-not $CkEula.IsChecked) { Show-Msg 'Minecraft EULA에 동의해야 서버를 설치·실행할 수 있습니다.' 'TailCraft' 'Warning'; return }
    if ($script:ServerState -ne 'Stopped') { Show-Msg '서버를 먼저 중지하세요.' 'TailCraft' 'Warning'; return }
    Save-Settings
    $c = $script:Cfg
    Start-BgTask '서버 설치 중' '준비 중...' @{ loader = $c.loader; mc = $c.mcVersion; lv = $c.loaderVersion } {
        Install-Server $P.loader $P.mc $P.lv $Status
    } {
        param($S)
        if ($S.Error) { Show-Msg "설치 실패:`n$($S.Error)" 'TailCraft' 'Error'; return }
        $script:Cfg.installedKey = Get-InstalledKey
        Save-Config $script:Cfg
        Write-ServerProperties $script:Cfg
        Write-Eula
        Update-InstallState; Update-Dashboard; Refresh-RecPanel; Refresh-ModGrid
        if ($script:Cfg.autoEssentials) {
            $defs = @(Get-RecommendedSet $script:Cfg.loader | Where-Object { $_.Default })
            if ($defs.Count -gt 0) { Install-RecSet $defs "설치 완료! 기본 세트($(($defs | ForEach-Object { $_.Title }) -join ', '))도 설치했습니다.`n대시보드에서 '서버 시작'을 누르세요."; return }
        }
        Show-Msg "설치 완료! Java: $($S.Result)`n대시보드에서 '서버 시작'을 누르세요."
    }
}

# ============================================================ 서버 프로세스
function Start-ServerProc {
    if ($script:ServerState -ne 'Stopped') { return }
    if (-not (Test-Installed)) { Show-Msg '먼저 설정 탭에서 서버를 설치하세요.' 'TailCraft' 'Warning'; $Tabs.SelectedIndex = 1; return }
    if (-not $script:Cfg.eulaAccepted) { Show-Msg 'EULA에 동의해야 합니다 (설정 탭).' 'TailCraft' 'Warning'; $Tabs.SelectedIndex = 1; return }
    try { $spec = Get-LaunchArgs $script:Cfg } catch { Show-Msg $_.Exception.Message 'TailCraft' 'Error'; return }
    if (-not $spec.Java) { Show-Msg 'Java를 찾지 못했습니다. 설정 탭에서 재설치하세요.' 'TailCraft' 'Error'; return }
    Write-ServerProperties $script:Cfg; Write-Eula

    if ($script:Cfg.networkMode -eq 'portforward' -and $script:Cfg.upnp) {
        $lip = (Get-LocalIPv4).IP
        if ($lip) { $script:UpnpPort = [int]$script:Cfg.port; $ok = Add-UpnpMapping $script:Cfg.port $lip; $UpnpState.Text = if ($ok) { '✔ UPnP 개방됨' } else { '✖ UPnP 실패 — 수동 포트포워딩 필요' } }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $spec.Java
    $psi.Arguments = ($spec.Args | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $psi.WorkingDirectory = Get-ServerDir
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = New-Object System.Diagnostics.Process; $p.StartInfo = $psi
    Append-Log "[TailCraft] $($spec.Java) $($psi.Arguments)"
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    try { [void]$p.Start() } catch { Show-Msg "서버 실행 실패: $($_.Exception.Message)" 'TailCraft' 'Error'; return }
    $script:Proc = $p; $script:ProcStart = Get-Date; $script:ServerState = 'Starting'; $script:NeedRestart = $false
    Write-TcLog "서버 시작 PID $($p.Id)"
    $script:Players.Clear(); $script:LastCpuTime = [TimeSpan]::Zero; $script:LastCpuCheck = Get-Date

    foreach ($streamName in 'StandardOutput', 'StandardError') {
        $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
        $rs.SessionStateProxy.SetVariable('Proc', $p); $rs.SessionStateProxy.SetVariable('Q', $script:LogQueue); $rs.SessionStateProxy.SetVariable('SN', $streamName)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript('$r = $Proc.$SN; while ($true) { $l = $r.ReadLine(); if ($null -eq $l) { break }; $Q.Enqueue($l) }')
        $script:Readers += @{ PS = $ps; RS = $rs; H = $ps.BeginInvoke() }
    }
    Update-Dashboard
}

function Stop-ServerProc([switch]$Force) {
    if (-not $script:Proc -or $script:Proc.HasExited) { Finish-ServerExit; return }
    $script:ServerState = 'Stopping'; Update-Dashboard
    try { $script:Proc.StandardInput.WriteLine('stop') } catch {}
    if ($Force) { try { $script:Proc.Kill() } catch {} }
}

function Finish-ServerExit {
    if ($script:Proc) {
        try { Append-Log "[TailCraft] 서버 종료 (exit $($script:Proc.ExitCode))" } catch {}
        $script:Proc.Dispose()
    }
    $script:Proc = $null; $script:ServerState = 'Stopped'; $script:Players.Clear()
    $keep = @(); foreach ($r in $script:Readers) { if ($r.H.IsCompleted) { try { $r.PS.Dispose(); $r.RS.Dispose() } catch {} } else { $keep += $r } }; $script:Readers = $keep
    if ($script:UpnpPort) { try { Remove-UpnpMapping $script:UpnpPort } catch {}; $script:UpnpPort = 0 }
    if ($script:PendingRestart) { $script:PendingRestart = $false; Start-ServerProc }
    Update-Dashboard
}

function Send-Command($cmd) {
    if ($script:Proc -and -not $script:Proc.HasExited) {
        try { $script:Proc.StandardInput.WriteLine($cmd); Append-Log "> $cmd" } catch { Append-Log "[TailCraft] 전송 실패: $($_.Exception.Message)" }
    } else { Append-Log '[TailCraft] 서버가 실행 중이 아닙니다.' }
}

# ============================================================ 대시보드 갱신
function Get-ConnectAddress {
    $c = $script:Cfg
    $portSfx = if ([int]$c.port -ne 25565) { ":$($c.port)" } else { '' }
    switch ($c.networkMode) {
        'tailscale' {
            $st = $script:TsCache
            if ($st -and $st.State -eq 'Running') {
                $addr = if ($st.DNSName) { $st.DNSName } else { $st.IPv4 }
                return @{ Addr = "$addr$portSfx"; Mode = '테일스케일 — 친구 PC에도 Tailscale이 켜져 있어야 합니다'; Hint = "IP로도 접속 가능: $($st.IPv4)$portSfx" }
            }
            return @{ Addr = '-'; Mode = '테일스케일 — 아직 연결되지 않음'; Hint = '네트워크 탭에서 설치·로그인하세요.' }
        }
        'portforward' {
            $pub = $PfPublic.Text
            if ($pub) { return @{ Addr = "$pub$portSfx"; Mode = '포트포워딩 — 공인 IP로 접속'; Hint = '공유기 포트포워딩 + 방화벽이 열려 있어야 합니다. 공인 IP는 바뀔 수 있어요.' } }
            return @{ Addr = '-'; Mode = '포트포워딩 — 공인 IP 미조회'; Hint = '네트워크 탭에서 공인 IP 조회를 누르세요.' }
        }
        default {
            if (-not $script:LanCache) { $script:LanCache = Get-LocalIPv4 }
            $lip = $script:LanCache.IP
            return @{ Addr = "$lip$portSfx"; Mode = 'LAN — 같은 공유기 안에서만'; Hint = '' }
        }
    }
}

function Update-Dashboard {
    $c = $script:Cfg
    $running = ($script:ServerState -ne 'Stopped')
    $BtnStart.IsEnabled = -not $running; $BtnStop.IsEnabled = $running; $BtnRestart.IsEnabled = ($script:ServerState -eq 'Running')
    switch ($script:ServerState) {
        'Stopped'  { $StateDot.Fill = $W.FindResource('Bad');  $StateText.Text = '중지됨' }
        'Starting' { $StateDot.Fill = $W.FindResource('Warn'); $StateText.Text = '시작 중...' }
        'Running'  { $StateDot.Fill = $W.FindResource('Good'); $StateText.Text = '실행 중' }
        'Stopping' { $StateDot.Fill = $W.FindResource('Warn'); $StateText.Text = '종료 중...' }
    }
    if (Test-Installed) {
        $DashTitle.Text = "$(($c.loader).Substring(0,1).ToUpper() + ($c.loader).Substring(1)) $($c.mcVersion)"
        $DashSub.Text = "빌드 $($c.loaderVersion) · 포트 $($c.port) · 최대 $($c.maxPlayers)명 · Java $(Get-RequiredJava $c.mcVersion)"
    } else { $DashTitle.Text = '서버가 설치되지 않았습니다'; $DashSub.Text = '설정 탭에서 서버 종류와 버전을 고른 뒤 설치하세요.' }
    $DashRestartHint.Visibility = if ($script:NeedRestart -and $running) { 'Visible' } else { 'Collapsed' }
    $TopInfo.Text = "$($script:SysInfo.HostName) · RAM $([math]::Round($script:SysInfo.TotalRamMB/1024,1)) GB · $($script:SysInfo.Cores) 코어"
    $CpuSub.Text = "이 PC 논리 코어 $($script:SysInfo.Cores)개 기준"
    $RamSub.Text = "PC 전체 $([math]::Round($script:SysInfo.TotalRamMB/1024,1)) GB 중 $([math]::Round([int]$c.ramMB/1024,1)) GB 할당 ($([math]::Round(100*[int]$c.ramMB/$script:SysInfo.TotalRamMB))%)"
    $RamBar.Maximum = [int]$c.ramMB
    $PlayerCount.Text = "$($script:Players.Count) / $($c.maxPlayers)"
    $PlayerList.Items.Clear(); foreach ($pl in $script:Players) { [void]$PlayerList.Items.Add($pl) }
    $a = Get-ConnectAddress
    $AddrBox.Text = $a.Addr; $AddrMode.Text = $a.Mode; $AddrHint.Text = $a.Hint
    if (-not $running) { $CpuText.Text = '0 %'; $CpuBar.Value = 0; $RamText.Text = "0 / $($c.ramMB) MB"; $RamBar.Value = 0; $DashUptime.Text = '--:--:--' }
}

function Update-Metrics {
    if (-not $script:Proc) { return }
    try {
        if ($script:Proc.HasExited) { Finish-ServerExit; return }
        $script:Proc.Refresh()
        $now = Get-Date
        $cpu = $script:Proc.TotalProcessorTime
        $dt = ($now - $script:LastCpuCheck).TotalSeconds
        if ($dt -gt 0.5) {
            $pct = [math]::Min(100, [math]::Round(100 * ($cpu - $script:LastCpuTime).TotalSeconds / $dt / $script:SysInfo.Cores))
            $CpuText.Text = "$pct %"; $CpuBar.Value = $pct
            $script:LastCpuTime = $cpu; $script:LastCpuCheck = $now
        }
        $ws = [math]::Round($script:Proc.WorkingSet64 / 1MB)
        $RamText.Text = "$ws / $($script:Cfg.ramMB) MB"; $RamBar.Value = [math]::Min($ws, $RamBar.Maximum)
        $ts = $now - $script:ProcStart; $DashUptime.Text = '{0:00}:{1:mm\:ss}' -f [int][math]::Floor($ts.TotalHours), $ts
    } catch {}
}

function Update-Disk {
    $sdir = Get-ServerDir
    $mb = Get-FolderSizeMB $sdir
    $DiskText.Text = if ($mb -ge 1024) { "$([math]::Round($mb/1024,2)) GB" } else { "$mb MB" }
    try { $drv = Get-PSDrive ($global:TcRoot.Substring(0,1)); $DiskSub.Text = "드라이브 여유 공간 $([math]::Round($drv.Free/1GB,1)) GB" } catch {}
}

function Process-LogQueue {
    $line = $null; $n = 0
    while ($script:LogQueue.TryDequeue([ref]$line)) {
        Append-Log $line; $n++
        if ($line -match '\]: Done \(') { $script:ServerState = 'Running'; Update-Dashboard }
        elseif ($line -match 'UUID of player (\S+) is ([0-9a-fA-F-]{36})') { Register-PlayerInfo $Matches[1] -UUID $Matches[2] }
        elseif ($line -match '\]: (\S+)\[/([0-9a-fA-F:.]+?)(?::\d+)?\] logged in with entity id') { Register-PlayerInfo $Matches[1] -IP $Matches[2] }
        elseif ($line -match '\]: (\S+) joined the game') { if (-not $script:Players.Contains($Matches[1])) { $script:Players.Add($Matches[1]) }; Register-PlayerInfo $Matches[1] -Joined; Update-PlayersUi }
        elseif ($line -match '\]: (\S+) left the game') { [void]$script:Players.Remove($Matches[1]); Update-PlayersUi; Refresh-PlayerGrid }
        elseif ($line -match 'FAILED TO BIND TO PORT') { Show-Msg "포트 $($script:Cfg.port) 가 이미 사용 중입니다. 다른 서버가 켜져 있거나 포트를 바꿔야 합니다." 'TailCraft' 'Error' }
        elseif ($line -match 'You need to agree to the EULA') { Show-Msg 'EULA 동의가 필요합니다. 설정 탭에서 체크 후 저장하세요.' 'TailCraft' 'Warning' }
        if ($n -gt 400) { break }
    }
}
function Update-PlayersUi {
    $PlayerCount.Text = "$($script:Players.Count) / $($script:Cfg.maxPlayers)"
    $PlayerList.Items.Clear(); foreach ($pl in $script:Players) { $ip = if ($script:PlayerDb.ContainsKey($pl)) { $script:PlayerDb[$pl].IP } else { '' }; [void]$PlayerList.Items.Add($(if ($ip) { "$pl  —  $ip" } else { $pl })) }
}

# ============================================================ 플레이어 DB
function Get-PlayerDbPath { return (Join-Path $global:TcRoot 'players.json') }
function Load-PlayerDb {
    $script:PlayerDb = @{}
    $p = Get-PlayerDbPath
    if (Test-Path $p) {
        try { $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($pr in $j.PSObject.Properties) { $h = @{}; foreach ($q in $pr.Value.PSObject.Properties) { $h[$q.Name] = $q.Value }; $script:PlayerDb[$pr.Name] = $h } } catch {}
    }
}
function Save-PlayerDb { try { ($script:PlayerDb | ConvertTo-Json -Depth 4) | Set-Content (Get-PlayerDbPath) -Encoding UTF8 } catch {} }

function Get-MacForIp($ip) {
    # 같은 LAN 일 때만 ARP 테이블에 있음
    if (-not $ip -or $ip -match '^(100\.|127\.)') { return '' }
    try { $n = Get-NetNeighbor -IPAddress $ip -ErrorAction SilentlyContinue | Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' } | Select-Object -First 1; if ($n) { return $n.LinkLayerAddress } } catch {}
    return ''
}
function Get-TsDeviceForIp($ip) {
    if (-not $ip -or $ip -notmatch '^100\.') { return '' }
    if ($script:TsCache -and $script:TsCache.Peers) { $pe = $script:TsCache.Peers | Where-Object { $_.IP -eq $ip } | Select-Object -First 1; if ($pe) { return "$($pe.Name) ($($pe.OS))" } }
    return '(공유 노드로 접속)'
}

function Register-PlayerInfo($name, $UUID, $IP, [switch]$Joined) {
    if (-not $script:PlayerDb.ContainsKey($name)) { $script:PlayerDb[$name] = @{ Name = $name; UUID = ''; IP = ''; MAC = ''; Device = ''; LastSeen = ''; Count = 0 } }
    $e = $script:PlayerDb[$name]
    if ($UUID) { $e.UUID = $UUID }
    if ($IP) {
        $e.IP = $IP
        $e.Device = Get-TsDeviceForIp $IP
        if ($IP -notmatch '^100\.') { $e.MAC = Get-MacForIp $IP }
    }
    if ($Joined) { $e.LastSeen = (Get-Date).ToString('yyyy-MM-dd HH:mm'); $e.Count = [int]$e.Count + 1; Save-PlayerDb; Refresh-PlayerGrid }
}

function Read-ServerJsonNames($file) {
    $p = Join-Path (Get-ServerDir) $file
    if (-not (Test-Path $p)) { return @() }
    try { return @((Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_.name }) } catch { return @() }
}

function Refresh-PlayerGrid {
    $wl = Read-ServerJsonNames 'whitelist.json'; $ops = Read-ServerJsonNames 'ops.json'; $bans = Read-ServerJsonNames 'banned-players.json'
    $rows = New-Object System.Collections.ArrayList
    foreach ($e in ($script:PlayerDb.Values | Sort-Object { $script:Players.Contains($_.Name) } -Descending)) {
        $st = if ($script:Players.Contains($e.Name)) { '🟢 접속' } elseif ($bans -contains $e.Name) { '⛔ 밴' } else { '' }
        $mac = $e.MAC
        if (-not $mac -and $e.IP -and $e.IP -notmatch '^(100\.|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)') { $mac = '(인터넷 — 불가)' }
        [void]$rows.Add([pscustomobject]@{
            Status = $st; Name = $e.Name; IP = $e.IP; MAC = $mac; Device = $e.Device
            WL = $(if ($wl -contains $e.Name) { '✔' } else { '' }); OP = $(if ($ops -contains $e.Name) { '★' } else { '' })
            LastSeen = $e.LastSeen; Count = $e.Count; UUID = $e.UUID
        })
    }
    $sel = if ($PlayerGrid.SelectedItem) { $PlayerGrid.SelectedItem.Name } else { $null }
    $PlayerGrid.ItemsSource = $rows
    if ($sel) { foreach ($r in $rows) { if ($r.Name -eq $sel) { $PlayerGrid.SelectedItem = $r; break } } }
}

function Invoke-PlayerCmd($fmt) {
    $r = $PlayerGrid.SelectedItem
    if (-not $r) { Show-Msg '먼저 표에서 플레이어를 선택하세요.' 'TailCraft' 'Warning'; return }
    if ($script:ServerState -ne 'Running') { Show-Msg '서버가 실행 중일 때만 적용할 수 있습니다. (whitelist.json 등은 서버가 직접 관리)' 'TailCraft' 'Warning'; return }
    $cmd = $fmt -replace '\{name\}', $r.Name -replace '\{ip\}', $r.IP
    Send-Command $cmd
    $script:PlayerGridRefreshAt = (Get-Date).AddSeconds(1.5)
}

# ============================================================ 모드/플러그인
function Get-CurKind { if ($RbKindPlugin.IsChecked) { return 'plugin' } return 'mod' }
function Refresh-ModGrid {
    $loader = $script:Cfg.loader
    $canMod = Test-ModLoader $loader; $canPlug = Test-PluginLoader $loader
    $RbKindMod.IsEnabled = $canMod; $RbKindPlugin.IsEnabled = $canPlug
    if (-not $canMod -and $canPlug) { $RbKindPlugin.IsChecked = $true } elseif ($canMod -and -not $canPlug) { $RbKindMod.IsChecked = $true }
    $kind = Get-CurKind
    $ModsHint.Text = "$loader · server\$(if ($kind -eq 'plugin') {'plugins'} else {'mods'}) — $(if ($kind -eq 'plugin') {'플러그인은 서버에만 설치하면 됩니다.'} else {'모드는 친구도 같은 파일을 설치해야 합니다 (zip 내보내기).'})"
    $ModGrid.ItemsSource = @(Get-ContentList $loader $kind)
    $BtnModExport.IsEnabled = ($kind -eq 'mod')
}
function Refresh-RecPanel {
    $RecPanel.Children.Clear()
    $installed = @()
    foreach ($k in 'mod','plugin') { $installed += @(Get-ContentList $script:Cfg.loader $k | ForEach-Object { $_.File.ToLower() }) }
    foreach ($r in (Get-RecommendedSet $script:Cfg.loader)) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $has = ($installed | Where-Object { $_ -like "*$($r.Slug.Replace('-',''))*" -or $_ -like "*$($r.Slug)*" }).Count -gt 0
        $cb.Content = "$($r.Title)$(if ($has) {'  (설치됨)'})  — $($r.Note)"; $cb.IsChecked = ($r.Default -and -not $has); $cb.Tag = $r
        $cb.Foreground = $W.FindResource('Text')
        [void]$RecPanel.Children.Add($cb)
    }
    if ($RecPanel.Children.Count -eq 0) { $t = New-Object System.Windows.Controls.TextBlock; $t.Text = '이 로더용 추천 항목이 없습니다.'; $t.Foreground = $W.FindResource('Muted'); [void]$RecPanel.Children.Add($t) }
}
function Install-RecSet($items, $doneMsg) {
    $list = @($items | ForEach-Object { @{ Slug = $_.Slug; Kind = $_.Kind } })
    Start-BgTask '추천 세트 설치' '준비 중...' @{ items = $list; loader = $script:Cfg.loader; mc = $script:Cfg.mcVersion } {
        $r = @(); foreach ($it in $P.items) { & $Status "$($it.Slug) 설치 중..."; $r += Install-ModrinthProject $it.Slug $P.loader $P.mc $it.Kind $Status }; $r
    } {
        param($S)
        Refresh-ModGrid; Refresh-RecPanel
        if ($S.Error) { Show-Msg "일부 설치 실패: $($S.Error)" 'TailCraft' 'Warning'; return }
        $m = if ($doneMsg) { $doneMsg } else { "설치됨: $(@($S.Result) -join ', ')" }
        if ($script:ServerState -ne 'Stopped') { $m += "`n서버를 재시작해야 적용됩니다." }
        Show-Msg $m
    }
}
function Install-ModrinthUi($slug, $kind) {
    if (-not $script:Cfg.mcVersion) { Show-Msg '먼저 서버를 설치하세요.' 'TailCraft' 'Warning'; return }
    Start-BgTask 'Modrinth 설치' "$slug 다운로드 중..." @{ slug = $slug; kind = $kind; loader = $script:Cfg.loader; mc = $script:Cfg.mcVersion } {
        Install-ModrinthProject $P.slug $P.loader $P.mc $P.kind $Status
    } {
        param($S)
        Refresh-ModGrid; Refresh-RecPanel
        if ($S.Error) { Show-Msg "설치 실패: $($S.Error)" 'TailCraft' 'Error'; return }
        $m = "설치됨: $(@($S.Result) -join ', ')"; if ($script:ServerState -ne 'Stopped') { $m += "`n서버를 재시작해야 적용됩니다." }
        Show-Msg $m
    }
}

# ============================================================ 콘솔 빠른 명령 / 진단
$script:BuiltinCmds = @(
    @{ L = 'list';        C = 'list' },
    @{ L = 'tps';         C = 'tps' },
    @{ L = 'save-all';    C = 'save-all' },
    @{ L = '낮으로';      C = 'time set day' },
    @{ L = '날씨 맑음';   C = 'weather clear' },
    @{ L = '비 끄기';     C = 'gamerule doWeatherCycle false' },
    @{ L = '킵인벤';      C = 'gamerule keepInventory true' },
    @{ L = '화리 목록';   C = 'whitelist list' },
    @{ L = '밴 목록';     C = 'banlist' },
    @{ L = 'seed';        C = 'seed' },
    @{ L = '난이도 노멀'; C = 'difficulty normal' },
    @{ L = '전원 알림';   C = 'say [서버] ' ; Edit = $true },
    @{ L = 'gamemode';    C = 'gamemode creative '; Edit = $true },
    @{ L = 'tp';          C = 'tp '; Edit = $true },
    @{ L = 'give';        C = 'give @a minecraft:'; Edit = $true },
    @{ L = 'kick';        C = 'kick '; Edit = $true }
)
function Refresh-QuickCmds {
    $QuickCmdPanel.Children.Clear()
    $all = @($script:BuiltinCmds | ForEach-Object { $_ }) + @($script:Cfg.customCmds | Where-Object { $_ } | ForEach-Object { @{ L = $_; C = $_; Custom = $true } })
    foreach ($q in $all) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $(if ($q.Custom) { "★ $($q.L)" } else { $q.L }); $b.Tag = $q; $b.Padding = New-Object System.Windows.Thickness(9,3,9,3); $b.Margin = New-Object System.Windows.Thickness(2); $b.FontSize = 12
        $b.Style = $W.FindResource([System.Windows.Controls.Button])
        $b.ToolTip = $q.C
        $b.Add_Click({ param($s, $e) $q2 = $s.Tag; if ($q2.Edit) { $CmdBox.Text = $q2.C; $CmdBox.Focus(); $CmdBox.CaretIndex = $CmdBox.Text.Length } else { Send-Command $q2.C } })
        if ($q.Custom) { $b.Add_MouseRightButtonUp({ param($s, $e) $c = $s.Tag.C; if (Ask-YesNo "즐겨찾기 '$c' 를 삭제할까요?") { $script:Cfg.customCmds = @($script:Cfg.customCmds | Where-Object { $_ -ne $c }); Save-Config $script:Cfg; Refresh-QuickCmds } }) }
        [void]$QuickCmdPanel.Children.Add($b)
    }
}
function Get-Diagnostics {
    $c = $script:Cfg; $sb = New-Object System.Text.StringBuilder
    $add = { param($t) [void]$sb.AppendLine($t) }
    & $add "=== TailCraft 진단 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
    & $add "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) · PS $($PSVersionTable.PSVersion) · RAM $([math]::Round($script:SysInfo.TotalRamMB/1024,1))GB · $($script:SysInfo.Cores)코어"
    & $add "루트: $global:TcRoot"
    & $add "서버: $($c.loader) $($c.mcVersion) ($($c.loaderVersion)) · 설치키=$($c.installedKey) · 상태=$($script:ServerState)"
    $jm = Get-RequiredJava $c.mcVersion; $jp = Find-Java $jm
    & $add "Java 필요=$jm · 경로=$(if ($jp) { $jp } else { '(없음)' }) · 감지버전=$(if ($jp) { Get-JavaMajor $jp } else { '-' })"
    & $add "RAM 할당=$($c.ramMB)MB · 포트=$($c.port) · online-mode=$($c.onlineMode) · whitelist=$($c.whitelist) · EULA=$($c.eulaAccepted)"
    $po = Get-PortOwner $c.port; & $add "포트 $($c.port) 점유: $(if ($po) { $po } else { '없음' })"
    & $add "방화벽 규칙(TCP $($c.port)): $(if (Test-FirewallRule $c.port) { 'OK' } else { '없음 ← 친구 접속 차단 원인' })"
    & $add "네트워크 모드: $($c.networkMode)"
    $lip = Get-LocalIPv4; & $add "내부 IP=$($lip.IP) · 게이트웨이=$($lip.Gateway) · 어댑터=$($lip.Adapter)"
    $ts = Get-TailscaleStatus; & $add "Tailscale: 설치=$($ts.Installed) · 상태=$($ts.State) · IP=$($ts.IPv4) · DNS=$($ts.DNSName) · 피어=$($ts.Peers.Count)"
    if ($c.networkMode -eq 'portforward') { & $add "UPnP 매핑: $(Test-UpnpMapping $c.port) · 공인IP=$($PfPublic.Text)" }
    try { $drv = Get-PSDrive ($global:TcRoot.Substring(0,1)); & $add "디스크 여유: $([math]::Round($drv.Free/1GB,1)) GB · 서버 폴더 $(Get-FolderSizeMB (Get-ServerDir)) MB" } catch {}
    $sp = Join-Path (Get-ServerDir) 'server.properties'
    if (Test-Path $sp) { & $add "--- server.properties (주요) ---"; Get-Content $sp -Encoding UTF8 | Where-Object { $_ -match '^(server-port|max-players|online-mode|white-list|view-distance|level-name|motd|server-ip)=' } | ForEach-Object { & $add "  $_" } }
    foreach ($k in 'mod','plugin') { $l = @(Get-ContentList $c.loader $k); if ($l.Count) { & $add "--- $k ($($l.Count)) ---"; $l | ForEach-Object { & $add "  $($_.Enabled) $($_.File)" } } }
    $cp = Join-Path (Get-ServerDir) 'crash-reports'
    if (Test-Path $cp) { $cr = Get-ChildItem $cp -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($cr) { & $add "최근 크래시: $($cr.Name) ($($cr.LastWriteTime))" } }
    & $add "--- 콘솔 최근 50줄 ---"
    ($ConsoleBox.Text -split "`r`n" | Where-Object { $_ } | Select-Object -Last 50) | ForEach-Object { & $add $_ }
    return $sb.ToString()
}

# ============================================================ 네트워크
function Update-NetPanels {
    $mode = if ($RbPortfwd.IsChecked) { 'portforward' } elseif ($RbLan.IsChecked) { 'lan' } else { 'tailscale' }
    $PanelTs.Visibility = if ($mode -eq 'tailscale') { 'Visible' } else { 'Collapsed' }
    $PanelPf.Visibility = if ($mode -eq 'portforward') { 'Visible' } else { 'Collapsed' }
    $PanelLan.Visibility = if ($mode -eq 'lan') { 'Visible' } else { 'Collapsed' }
    $script:LanCache = Get-LocalIPv4; $lip = $script:LanCache
    $PfLocal.Text = $lip.IP; $PfGw.Text = $lip.Gateway
    $port = [int]$script:Cfg.port
    $portSfx = if ($port -ne 25565) { ":$port" } else { '' }
    $LanAddr.Text = "$($lip.IP)$portSfx"
    $FwState.Text = if (Test-FirewallRule $port) { "✔ 방화벽 허용 규칙 있음 (TCP $port)" } else { "✖ 방화벽 규칙 없음 — 친구 접속이 차단됩니다 (TCP $port)" }
}

function Refresh-Tailscale {
    $st = Get-TailscaleStatus
    $script:TsCache = $st
    switch ($st.State) {
        'NotInstalled' { $TsDot.Fill = $W.FindResource('Bad');  $TsState.Text = '설치 안 됨'; $BtnTsInstall.IsEnabled = $true;  $BtnTsLogin.IsEnabled = $false }
        'Running'      { $TsDot.Fill = $W.FindResource('Good'); $TsState.Text = '연결됨';     $BtnTsInstall.IsEnabled = $false; $BtnTsLogin.IsEnabled = $false }
        'NeedsLogin'   { $TsDot.Fill = $W.FindResource('Warn'); $TsState.Text = '로그인 필요'; $BtnTsInstall.IsEnabled = $false; $BtnTsLogin.IsEnabled = $true }
        default        { $TsDot.Fill = $W.FindResource('Warn'); $TsState.Text = "$($st.State)"; $BtnTsInstall.IsEnabled = $false; $BtnTsLogin.IsEnabled = $true }
    }
    $TsIp.Text = $st.IPv4; $TsDns.Text = $st.DNSName; $TsUser.Text = if ($st.LoginName) { $st.LoginName } else { '-' }
    $TsPeers.Items.Clear()
    foreach ($pe in $st.Peers) { [void]$TsPeers.Items.Add("$(if ($pe.Online) {'🟢'} else {'⚫'}) $($pe.Name)  ($($pe.IP), $($pe.OS))") }
    if ($TsPeers.Items.Count -eq 0) { [void]$TsPeers.Items.Add('(아직 없음)') }
    Update-Dashboard
}

function Get-InviteText {
    $c = $script:Cfg; $a = Get-ConnectAddress
    switch ($c.networkMode) {
        'tailscale' {
            $ip = "$($script:TsCache.IPv4)"; if ([int]$c.port -ne 25565) { $ip += ":$($c.port)" }
            $link = "$($c.tsShareLink)"
            $step3 = if ($link) { "3. 이 링크를 브라우저로 열고 Accept 누르기 (로그인 상태에서)`n   $link`n   → Tailscale 기기 목록에 '$($script:TsCache.DNSName -split '\.' | Select-Object -First 1)' 가 shared 로 뜨면 성공" } else { "3. 내가 보낸 공유 링크를 브라우저로 열고 Accept (로그인 상태에서)" }
            return "🎮 마인크래프트 서버 초대 (Tailscale)`n`n1. https://tailscale.com/download 에서 Tailscale 설치`n2. 아무 계정(구글/MS/깃허브/애플)으로 로그인 → 트레이 아이콘 'Connected' 확인`n$step3`n4. 마인크래프트 → 멀티플레이 → 서버 추가`n   주소: $ip`n   버전: $($c.mcVersion) ($($c.loader))`n`n※ 접속 안 되면: Tailscale 켜져 있는지 → cmd에서 ping $($script:TsCache.IPv4) 되는지 확인`n※ 링크는 다른 사람에게 주지 마세요"
        }
        'portforward' { return "🎮 마인크래프트 서버 초대`n`n마인크래프트 → 멀티플레이 → 서버 추가`n주소: $($a.Addr)`n버전: $($c.mcVersion) ($($c.loader))" }
        default { return "🎮 마인크래프트 서버 (같은 와이파이/공유기)`n`n주소: $($a.Addr)`n버전: $($c.mcVersion) ($($c.loader))" }
    }
}

# ============================================================ 튜토리얼
$script:TutSteps = @(
    @{ Tab = 0; Title = 'TailCraft에 오신 걸 환영합니다 👋'; Body = "이 런처는 마인크래프트 서버 설치·실행·친구 초대를 한 화면에서 끝내줍니다. 8단계 안내를 따라가면서 실제 버튼을 눌러 보세요. 언제든 '건너뛰기'로 닫고, 도움말 탭에서 다시 볼 수 있습니다."; Hl = 'CardStatus' },
    @{ Tab = 1; Title = '1단계 · 서버 종류와 버전 고르기'; Body = "Paper = 플러그인·최적화(대부분 여기), Fabric = 가벼운 모드, NeoForge/Forge = 큰 모드팩. 종류를 고르면 버전 목록이 자동으로 내려옵니다. 친구들과 같은 마인크래프트 버전이어야 합니다. 로더/빌드는 맨 위(최신)를 쓰면 됩니다."; Hl = 'CardSoftware' },
    @{ Tab = 1; Title = '2단계 · 메모리 할당'; Body = "슬라이더로 서버에 줄 RAM을 정합니다. 친구 2~5명 바닐라/Paper는 2~4 GB, 모드팩은 6 GB 이상. PC 전체 RAM의 절반을 넘기지 마세요 — 윈도우와 게임 클라이언트도 메모리가 필요합니다. 나중에 대시보드에서도 바로 바꿀 수 있습니다."; Hl = 'CardRes' },
    @{ Tab = 1; Title = '3단계 · 게임 설정과 EULA'; Body = "포트는 특별한 이유 없으면 25565 그대로. 정품 인증은 켜두는 걸 권장(사칭 방지). EULA 체크 후 '설정 저장'을 누르세요. 체크하지 않으면 서버가 켜지자마자 꺼집니다."; Hl = 'CardEula' },
    @{ Tab = 2; Title = '4단계 · 친구 접속 방식 선택'; Body = "테일스케일: 공유기 손 안 대고 가장 쉬움, 친구도 앱 설치. 포트포워딩: 친구는 아무것도 안 깔지만 공유기 설정 필요. LAN: 같은 집/PC방 전용. 고르면 아래에 해당 패널만 보입니다."; Hl = 'CardNetMode' },
    @{ Tab = 2; Title = '5단계 · 네트워크 연결'; Body = ''; Hl = 'DYNAMIC' },
    @{ Tab = 2; Title = '6단계 · 방화벽 열기'; Body = "어떤 방식이든 Windows 방화벽이 서버 포트를 막고 있으면 친구가 못 들어옵니다. '방화벽 허용 규칙 추가'를 누르고 관리자 권한 창에서 '예'. 한 번만 하면 됩니다. 더 자세한 내용은 PDF 설명서를 보세요."; Hl = 'CardFw' },
    @{ Tab = 1; Title = '7단계 · 설치'; Body = "'설치 / 재설치'를 누르면 필요한 Java와 서버 파일을 자동으로 내려받습니다(모드 서버는 몇 분 걸림). 완료 메시지가 뜨면 다음으로."; Hl = 'CardSoftware' },
    @{ Tab = 0; Title = '8단계 · 서버 시작 & 친구 초대'; Body = "오른쪽 위 '서버 시작'을 누르고 콘솔에 Done 이 뜨면 준비 끝. '친구용 안내문 복사'를 눌러 카톡/디스코드에 붙여넣으면 친구가 그대로 따라 들어올 수 있습니다. 즐거운 플레이 되세요!"; Hl = 'CardAddr' }
)
$script:TutHlCards = @('CardStatus','CardSoftware','CardRes','CardEula','CardNetMode','PanelTs','PanelPf','PanelLan','CardFw','CardAddr','CardRam','CardPlayers','CardMods','CardRecommend')

function Show-TutStep($i) {
    $i = [int]$i
    foreach ($n in $script:TutHlCards) { (Get-Variable $n -ValueOnly).BorderBrush = [System.Windows.Media.Brushes]::Transparent }
    if ($i -lt 0 -or $i -ge $script:TutSteps.Count) { $script:TutStep = -1; $TutBanner.Visibility = 'Collapsed'; if (-not $script:Cfg.firstRunDone) { $script:Cfg.firstRunDone = $true; Save-Config $script:Cfg }; return }
    $script:TutStep = $i; $s = $script:TutSteps[$i]
    $Tabs.SelectedIndex = $s.Tab
    $TutStepText.Text = "튜토리얼 $($i+1) / $($script:TutSteps.Count)"; $TutTitle.Text = $s.Title
    $hl = $s.Hl; $body = $s.Body
    if ($hl -eq 'DYNAMIC') {
        if ($RbPortfwd.IsChecked) { $hl = 'PanelPf'; $body = "'조회'로 공인 IP를 확인하고, UPnP 체크 후 '지금 UPnP 개방 시도'. ✔가 뜨면 끝. ✖면 '관리 페이지 열기'로 공유기에 들어가 포트포워딩을 직접 추가해야 합니다(PDF 4장에 제조사별 메뉴 위치). 서버를 켠 뒤 '외부에서 포트 열림 확인'으로 검증하세요." }
        elseif ($RbLan.IsChecked) { $hl = 'PanelLan'; $body = "같은 공유기 안이라면 표시된 내부 IP로 바로 접속됩니다. 다음 단계의 방화벽만 열면 끝." }
        else { $hl = 'PanelTs'; $body = "'1. 테일스케일 설치' → UAC '예' → '2. 로그인 / 연결' → 브라우저에서 구글/MS 계정 로그인 → 상태 '연결됨' 확인. 그다음 친구 초대: '관리 콘솔 열기' → 서버 PC 행 ··· → Share… → Copy invite link 탭 → Reusable link 켜고 복사 → 아래 '공유 링크' 칸에 붙여넣기 → 설정 저장. 친구는 자기 계정으로 Tailscale 로그인 후 그 링크를 열어 Accept 하면 기기 목록에 내 서버가 생기고, 표시된 Tailscale IP로 접속합니다. (친구 수 제한 없음, 친구는 서버 PC 외엔 아무것도 못 봄)" }
    }
    $TutBody.Text = $body
    (Get-Variable $hl -ValueOnly).BorderBrush = $W.FindResource('Accent')
    $el = Get-Variable $hl -ValueOnly
    $W.Dispatcher.BeginInvoke([Action]{ $el.BringIntoView() }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
    $BtnTutPrev.IsEnabled = ($i -gt 0)
    $BtnTutNext.Content = if ($i -eq $script:TutSteps.Count - 1) { '완료 ✔' } else { '다음 ▶' }
    $TutBanner.Visibility = 'Visible'
}

# ============================================================ 이벤트
$BtnStart.Add_Click({ Start-ServerProc })
$BtnStop.Add_Click({ Stop-ServerProc })
$BtnRestart.Add_Click({ $script:PendingRestart = $true; Stop-ServerProc })
$BtnOpenFolder.Add_Click({ $d = Get-ServerDir; if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null }; Start-Process explorer.exe $d })
$BtnOpenRoot.Add_Click({ Start-Process explorer.exe $global:TcRoot })
$BtnLicense.Add_Click({ $lp = Get-LicensePath; if ($lp) { Start-Process notepad.exe $lp } else { Show-Msg 'LICENSE.txt 가 없습니다.' 'TailCraft' 'Warning' } })
$BtnCopyAddr.Add_Click({ Set-Clip $AddrBox.Text })
$BtnCopyInvite.Add_Click({ Set-Clip (Get-InviteText); Show-Msg '친구용 안내문을 복사했습니다. 카톡/디스코드에 붙여넣으세요.' })
$DashRamSlider.Add_ValueChanged({ $DashRamVal.Text = "$([int]$DashRamSlider.Value) MB" })
$BtnDashRamApply.Add_Click({
    $RamSlider.Value = $DashRamSlider.Value; Save-Settings
    if ($script:ServerState -ne 'Stopped') { if (Ask-YesNo '메모리 변경은 재시작해야 적용됩니다. 지금 재시작할까요?') { $script:PendingRestart = $true; Stop-ServerProc } }
})
$RamSlider.Add_ValueChanged({
    $v = [int]$RamSlider.Value; $RamVal.Text = "$v MB"; $DashRamSlider.Value = $v
    $pct = [math]::Round(100 * $v / $script:SysInfo.TotalRamMB)
    $RamAdvice.Text = if ($pct -gt 60) { "⚠ PC RAM의 $pct% — 너무 많습니다. 윈도우/게임이 느려질 수 있어요." } elseif ($v -lt 2048) { '소규모 바닐라에만 적합. 모드 서버는 4 GB 이상 권장.' } else { "PC RAM의 $pct% 사용. 친구 2~5명 기준 적당합니다." }
    $RamAdvice.Foreground = if ($pct -gt 60) { $W.FindResource('Warn') } else { $W.FindResource('Muted') }
})
$CbLoader.Add_SelectionChanged({ if ($W.IsLoaded) { $CbLv.Items.Clear(); Load-McVersions } })
$CbMc.Add_SelectionChanged({ if ($W.IsLoaded -and $CbMc.SelectedItem -and $script:AutoLoadLv) { Load-LoaderVersions } })
$CbLv.Add_SelectionChanged({ if ($W.IsLoaded) { try { Read-SettingsFromUi } catch {}; Update-InstallState } })
$BtnRefreshVersions.Add_Click({ $script:AutoLoadLv = $true; Load-McVersions })
$BtnInstall.Add_Click({ Install-ServerUi })
$BtnSaveSettings.Add_Click({ Save-Settings; $m = '저장했습니다.'; if ($script:ServerState -ne 'Stopped') { $m += ' 실행 중인 서버는 재시작해야 적용됩니다.' }; Show-Msg $m })
$LinkEula.Add_RequestNavigate({ param($s, $e) Start-Process $e.Uri.AbsoluteUri })
foreach ($rb in $RbTailscale, $RbPortfwd, $RbLan) { $rb.Add_Checked({ if ($W.IsLoaded) { try { Read-SettingsFromUi } catch { Show-Msg '포트/인원/시야 값은 숫자여야 합니다.' 'TailCraft' 'Warning'; return }; Save-Config $script:Cfg; Update-NetPanels; Update-Dashboard } }) }
$BtnTsRefresh.Add_Click({ Refresh-Tailscale })
$BtnTsAdmin.Add_Click({ Start-Process 'https://login.tailscale.com/admin/machines' })
$BtnTsInstall.Add_Click({
    Start-BgTask '테일스케일 설치' '다운로드 준비...' @{} { Install-Tailscale $Status; 'ok' } { param($S) if ($S.Error) { Show-Msg "설치 실패: $($S.Error)" 'TailCraft' 'Error' }; Refresh-Tailscale }
})
$BtnTsLogin.Add_Click({
    Start-BgTask '테일스케일 로그인' '로그인 URL을 받는 중...' @{} { Start-TailscaleLogin } {
        param($S)
        if ($S.Error) { Show-Msg "실패: $($S.Error)" 'TailCraft' 'Error'; return }
        if ($S.Result -eq 'already') { Show-Msg '이미 연결되어 있습니다.' }
        elseif ($S.Result) { Start-Process $S.Result; Show-Msg "브라우저에서 로그인하세요. 로그인이 끝나면 '상태 새로고침'을 누르세요." }
        else { Show-Msg '로그인 URL을 얻지 못했습니다. 작업표시줄 Tailscale 아이콘에서 직접 Log in 하세요.' 'TailCraft' 'Warning' }
        Refresh-Tailscale
    }
})
$BtnCopyTsIp.Add_Click({ Set-Clip $TsIp.Text }); $BtnCopyTsDns.Add_Click({ Set-Clip $TsDns.Text })
$BtnPfPublic.Add_Click({ Start-BgTask '공인 IP 조회' '조회 중...' @{} { Get-PublicIP } { param($S) $PfPublic.Text = "$($S.Result)"; Update-Dashboard } })
$BtnPfGw.Add_Click({ if ($PfGw.Text) { Start-Process "http://$($PfGw.Text)" } })
$BtnUpnpNow.Add_Click({
    try { Read-SettingsFromUi } catch { Show-Msg '포트/인원/시야 값은 숫자여야 합니다.' 'TailCraft' 'Warning'; return }; Save-Config $script:Cfg
    $UpnpState.Text = 'UPnP 시도 중...'
    Start-BgTask 'UPnP 포트 개방' '공유기에 UPnP 요청 중 (최대 10초)...' @{ port = $script:Cfg.port; ip = (Get-LocalIPv4).IP } { Add-UpnpMapping $P.port $P.ip } {
        param($S)
        $UpnpState.Text = if ($S.Result -eq $true) { '✔ UPnP 개방됨' } else { '✖ UPnP 실패 — 공유기에서 UPnP를 켜거나 수동 포트포워딩' }
    }
})
$BtnPortCheck.Add_Click({ Open-PortChecker ([int]$script:Cfg.port) })
$BtnFw.Add_Click({ try { Add-FirewallRule ([int]$script:Cfg.port) } catch { Show-Msg "취소되었거나 실패: $($_.Exception.Message)" 'TailCraft' 'Warning' }; Update-NetPanels })
$openPdf = { $p = Join-Path $global:TcRoot 'TailCraft_Guide_KO.pdf'; if (-not (Test-Path $p)) { $p = Join-Path $script:AppDir 'TailCraft_Guide_KO.pdf' }; if (Test-Path $p) { Start-Process $p } else { Show-Msg 'TailCraft_Guide_KO.pdf 가 EXE 옆에 없습니다.' 'TailCraft' 'Warning' } }
$BtnOpenPdf.Add_Click($openPdf); $BtnOpenPdf2.Add_Click($openPdf)
$BtnSend.Add_Click({ if ($CmdBox.Text.Trim()) { Send-Command $CmdBox.Text.Trim(); $CmdBox.Clear() } })
$CmdBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $BtnSend.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })
$BtnClearLog.Add_Click({ $ConsoleBox.Clear() })
$BtnWlAdd.Add_Click({ Invoke-PlayerCmd 'whitelist add {name}' })
$BtnWlRemove.Add_Click({ Invoke-PlayerCmd 'whitelist remove {name}' })
$BtnOpAdd.Add_Click({ Invoke-PlayerCmd 'op {name}' })
$BtnOpRemove.Add_Click({ Invoke-PlayerCmd 'deop {name}' })
$BtnKick.Add_Click({ Invoke-PlayerCmd 'kick {name} TailCraft 관리자에 의해 추방됨' })
$BtnBan.Add_Click({ if ($PlayerGrid.SelectedItem -and (Ask-YesNo "$($PlayerGrid.SelectedItem.Name) 을(를) 밴할까요?")) { Invoke-PlayerCmd 'ban {name}' } })
$BtnBanIp.Add_Click({ if ($PlayerGrid.SelectedItem -and -not $PlayerGrid.SelectedItem.IP) { Show-Msg 'IP 정보가 없는 플레이어입니다.' 'TailCraft' 'Warning'; return }; if ($PlayerGrid.SelectedItem -and (Ask-YesNo "IP $($PlayerGrid.SelectedItem.IP) 를 밴할까요? (같은 IP의 모든 접속 차단)")) { Invoke-PlayerCmd 'ban-ip {ip}' } })
$BtnPardon.Add_Click({ Invoke-PlayerCmd 'pardon {name}'; if ($PlayerGrid.SelectedItem -and $PlayerGrid.SelectedItem.IP) { Invoke-PlayerCmd 'pardon-ip {ip}' } })
$BtnWlToggle.Add_Click({
    if ($script:ServerState -ne 'Running') { Show-Msg '서버가 실행 중일 때 전환할 수 있습니다. 꺼져 있을 땐 설정 탭의 체크박스를 쓰세요.' 'TailCraft' 'Warning'; return }
    $on = -not [bool]$script:Cfg.whitelist
    Send-Command $(if ($on) { 'whitelist on' } else { 'whitelist off' })
    $script:Cfg.whitelist = $on; $CkWhitelist.IsChecked = $on; Save-Config $script:Cfg; Write-ServerProperties $script:Cfg
    Show-Msg $(if ($on) { '화이트리스트 켬 — 목록에 없는 사람은 접속 불가' } else { '화이트리스트 끔 — 누구나 접속 가능' })
})
$BtnPlayersRefresh.Add_Click({ Refresh-PlayerGrid })
# 모드/플러그인
$RbKindMod.Add_Checked({ if ($W.IsLoaded) { Refresh-ModGrid } }); $RbKindPlugin.Add_Checked({ if ($W.IsLoaded) { Refresh-ModGrid } })
$BtnModRefresh.Add_Click({ Refresh-ModGrid; Refresh-RecPanel })
$BtnModFolder.Add_Click({ $d = Get-ContentDir $script:Cfg.loader (Get-CurKind); if (-not (Test-Path $d)) { New-Item -ItemType Directory $d -Force | Out-Null }; Start-Process explorer.exe $d })
$BtnModToggle.Add_Click({
    $r = $ModGrid.SelectedItem; if (-not $r) { Show-Msg '항목을 선택하세요.' 'TailCraft' 'Warning'; return }
    $new = if ($r.File -like '*.disabled') { $r.File -replace '\.disabled$', '' } else { "$($r.File).disabled" }
    try { Rename-Item $r.Path $new; Refresh-ModGrid; if ($script:ServerState -ne 'Stopped') { $script:NeedRestart = $true; Update-Dashboard } } catch { Show-Msg "변경 실패: $($_.Exception.Message)" 'TailCraft' 'Error' }
})
$BtnModDelete.Add_Click({
    $r = $ModGrid.SelectedItem; if (-not $r) { Show-Msg '항목을 선택하세요.' 'TailCraft' 'Warning'; return }
    if (Ask-YesNo "$($r.File) 을(를) 삭제할까요? (설정 폴더는 남습니다)") { try { Remove-Item $r.Path -Force; Refresh-ModGrid; Refresh-RecPanel } catch { Show-Msg "삭제 실패: $($_.Exception.Message)" 'TailCraft' 'Error' } }
})
$BtnModAdd.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog; $dlg.Filter = 'Jar 파일 (*.jar)|*.jar'; $dlg.Multiselect = $true
    if ($dlg.ShowDialog($W)) {
        $d = Get-ContentDir $script:Cfg.loader (Get-CurKind); if (-not (Test-Path $d)) { New-Item -ItemType Directory $d -Force | Out-Null }
        foreach ($f in $dlg.FileNames) { Copy-Item $f $d -Force }
        Refresh-ModGrid; if ($script:ServerState -ne 'Stopped') { $script:NeedRestart = $true; Update-Dashboard }
    }
})
$BtnModExport.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog; $dlg.Filter = 'Zip (*.zip)|*.zip'; $dlg.FileName = "mods-$($script:Cfg.loader)-$($script:Cfg.mcVersion).zip"
    if ($dlg.ShowDialog($W)) { try { Export-ModPack $script:Cfg.loader $dlg.FileName; Show-Msg "내보냈습니다:`n$($dlg.FileName)`n친구에게 보내서 자기 mods 폴더에 풀라고 하세요." } catch { Show-Msg $_.Exception.Message 'TailCraft' 'Error' } }
})
$BtnRecInstall.Add_Click({
    $sel = @($RecPanel.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) { Show-Msg '설치할 항목을 체크하세요.' 'TailCraft' 'Warning'; return }
    if (-not $script:Cfg.mcVersion) { Show-Msg '먼저 서버를 설치하세요.' 'TailCraft' 'Warning'; return }
    Install-RecSet $sel $null
})
$BtnMrSearch.Add_Click({
    $q = $MrQuery.Text.Trim(); if (-not $q) { return }
    if (-not $script:Cfg.mcVersion) { Show-Msg '먼저 서버를 설치하세요 (버전·로더 기준으로 검색합니다).' 'TailCraft' 'Warning'; return }
    Start-BgTask 'Modrinth 검색' "'$q' 검색 중..." @{ q = $q; loader = $script:Cfg.loader; mc = $script:Cfg.mcVersion; kind = (Get-CurKind) } { Search-Modrinth $P.q $P.loader $P.mc $P.kind } {
        param($S)
        $MrList.Items.Clear()
        if ($S.Error) { Show-Msg "검색 실패: $($S.Error)" 'TailCraft' 'Warning'; return }
        foreach ($h in $S.Result) { $it = New-Object System.Windows.Controls.ListBoxItem; $it.Content = "$($h.Title)   ↓$([math]::Round($h.Downloads/1000))k`n   $($h.Desc)"; $it.Tag = $h; $it.ToolTip = $h.Desc; [void]$MrList.Items.Add($it) }
        $MrInfo.Text = "$(@($S.Result).Count)개 결과 ($(Get-CurKind), $($script:Cfg.mcVersion))"
    }
})
$MrQuery.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $BtnMrSearch.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })
$BtnMrInstall.Add_Click({ $it = $MrList.SelectedItem; if (-not $it) { Show-Msg '검색 결과에서 항목을 선택하세요.' 'TailCraft' 'Warning'; return }; Install-ModrinthUi $it.Tag.Slug (Get-CurKind) })
# 콘솔 빠른 명령 / 진단
$BtnCmdSave.Add_Click({ $c = $CmdBox.Text.Trim(); if (-not $c) { return }; if ($script:Cfg.customCmds -notcontains $c) { $script:Cfg.customCmds = @($script:Cfg.customCmds) + $c; Save-Config $script:Cfg; Refresh-QuickCmds } })
$BtnDiag.Add_Click({ try { $t = Get-Diagnostics; $DiagBox.Text = $t; $DiagBox.Visibility = 'Visible'; Set-Clip $t; Write-TcLog '진단 실행'; Show-Msg '진단 결과를 클립보드에 복사했습니다. 질문할 때 그대로 붙여넣으세요.' } catch { Show-Msg "진단 실패: $($_.Exception.Message)" 'TailCraft' 'Error' } })
$BtnOpenLogs.Add_Click({ $d = Join-Path (Get-ServerDir) 'logs'; if (Test-Path $d) { Start-Process explorer.exe $d } else { Show-Msg '아직 logs 폴더가 없습니다 (서버를 한 번 실행하면 생깁니다).' } })
$BtnOpenLatestLog.Add_Click({ $f = Join-Path (Get-ServerDir) 'logs\latest.log'; if (Test-Path $f) { Start-Process notepad.exe $f } else { Show-Msg 'latest.log 가 없습니다.' } })
$BtnOpenCrash.Add_Click({ $d = Join-Path (Get-ServerDir) 'crash-reports'; if (Test-Path $d) { Start-Process explorer.exe $d } else { Show-Msg '크래시 리포트가 없습니다 — 좋은 소식입니다.' } })
$BtnOpenTcLog.Add_Click({ $f = Join-Path $global:TcRoot 'tailcraft.log'; if (Test-Path $f) { Start-Process notepad.exe $f } else { Show-Msg '런처 로그가 아직 없습니다.' } })
$BtnCopyConsole.Add_Click({ Set-Clip (($ConsoleBox.Text -split "`r`n" | Select-Object -Last 200) -join "`r`n"); Show-Msg '콘솔 최근 200줄을 복사했습니다.' })
$PlayerGrid.Add_SelectionChanged({ $r = $PlayerGrid.SelectedItem; $PlayerSelInfo.Text = if ($r) { "선택: $($r.Name)  ·  IP $($r.IP)  ·  화이트리스트 $(if ($r.WL) {'O'} else {'X'})  ·  OP $(if ($r.OP) {'O'} else {'X'})" } else { '행을 선택하세요' } })
$BtnTutorial.Add_Click({ Show-TutStep 0 })
$BtnTutNext.Add_Click({ Show-TutStep ($script:TutStep + 1) })
$BtnTutPrev.Add_Click({ Show-TutStep ($script:TutStep - 1) })
$BtnTutSkip.Add_Click({ Show-TutStep (-1) })

$W.Add_Closing({ param($s, $e)
    if ($script:ServerState -ne 'Stopped') {
        if (-not (Ask-YesNo '서버가 실행 중입니다. 안전하게 종료(stop)한 뒤 닫을까요?')) { $e.Cancel = $true; return }
        Stop-ServerProc
        $deadline = (Get-Date).AddSeconds(30)
        while ($script:Proc -and -not $script:Proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
        if ($script:Proc -and -not $script:Proc.HasExited) { try { $script:Proc.Kill() } catch {} }
    }
    if ($script:UpnpPort) { try { Remove-UpnpMapping $script:UpnpPort } catch {} }
})

# ============================================================ 타이머
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(400)
$Timer.Add_Tick({
    try { Process-LogQueue } catch { try { Append-Log "[TailCraft] 로그 처리 오류: $($_.Exception.Message)" } catch {} }
    # 백그라운드 작업 완료 처리
    for ($i = $script:BgTasks.Count - 1; $i -ge 0; $i--) {
        $t = $script:BgTasks[$i]
        if ($t.Sync.Done) {
            $script:BgTasks.RemoveAt($i)
            if ($script:BgTasks.Count -eq 0) { Set-Busy $null }
            try { $t.PS.Dispose(); $t.RS.Dispose() } catch {}
            try { if ($t.OnDone) { & $t.OnDone $t.Sync } } catch { Show-Msg "$($t.Title) 처리 오류: $($_.Exception.Message)" 'TailCraft' 'Error' }
        } else { $BusyText.Text = $t.Sync.Status }
    }
})
$Timer.Start()
$Timer2 = New-Object System.Windows.Threading.DispatcherTimer
$Timer2.Interval = [TimeSpan]::FromSeconds(2)
$Timer2.Add_Tick({ try { Update-Metrics; if ($script:PlayerGridRefreshAt -and (Get-Date) -gt $script:PlayerGridRefreshAt) { $script:PlayerGridRefreshAt = $null; Refresh-PlayerGrid } } catch {} })
$Timer2.Start()
$Timer3 = New-Object System.Windows.Threading.DispatcherTimer
$Timer3.Interval = [TimeSpan]::FromSeconds(20)
$Timer3.Add_Tick({ try { Update-Disk; if ($script:Cfg.networkMode -eq 'tailscale') { Refresh-Tailscale } } catch {} })
$Timer3.Start()

# ============================================================ 시작
$script:AutoLoadLv = $false
Load-SettingsToUi
$W.Dispatcher.Add_UnhandledException({ param($s, $e) $e.Handled = $true; try { Append-Log "[TailCraft] 오류: $($e.Exception.Message)" } catch {} })
$W.Add_Loaded({
    $script:AutoLoadLv = $true
    try { Refresh-Tailscale; Update-Disk; Update-Dashboard } catch {}
    try { Load-PlayerDb; Refresh-PlayerGrid } catch {}
    try { Refresh-ModGrid; Refresh-RecPanel; Refresh-QuickCmds } catch {}
    Write-TcLog "런처 시작 · $($script:Cfg.loader) $($script:Cfg.mcVersion)"
    if ($CbMc.Items.Count -le 1) { Load-McVersions }
    if (-not $script:Cfg.firstRunDone) { Show-TutStep 0 }
    elseif ($script:Cfg.autoStart) { Start-ServerProc }
})
# ============================================================ 라이선스 동의
function Get-LicensePath {
    foreach ($p in @((Join-Path $global:TcRoot 'LICENSE.txt'), (Join-Path $script:AppDir 'LICENSE.txt'))) { if (Test-Path $p) { return $p } }
    return $null
}
function Show-LicenseDialog {
    $lp = Get-LicensePath
    if (-not $lp) { [System.Windows.MessageBox]::Show('LICENSE.txt 파일이 없습니다. 배포본이 손상되었거나 임의로 변경되었습니다. 공식 배포본을 다시 받으세요.', 'TailCraft', 'OK', 'Error') | Out-Null; return $false }
    $text = Get-Content $lp -Raw -Encoding UTF8
    [xml]$lx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TailCraft 라이선스 계약" Width="760" Height="620" WindowStartupLocation="CenterScreen" Background="#1E1F26" FontFamily="Malgun Gothic" FontSize="13" ResizeMode="CanResize">
  <Grid Margin="18">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Foreground="#E6E6E6" FontSize="16" FontWeight="Bold" Text="계속하려면 아래 라이선스 계약을 읽고 동의해야 합니다." Margin="0,0,0,10"/>
    <TextBox x:Name="LicText" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#121318" Foreground="#D8DBE3" BorderBrush="#444857" Padding="10" FontSize="12.5"/>
    <DockPanel Grid.Row="2" Margin="0,12,0,0">
      <CheckBox x:Name="LicCheck" Foreground="#E6E6E6" VerticalAlignment="Center" Content="본인은 위 계약을 읽었으며, 수정·재배포·복제 금지 조항을 포함한 모든 조건에 동의합니다."/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="LicNo" Content="동의 안 함 (종료)" Padding="14,7" Margin="4" Background="#343745" Foreground="#E6E6E6" BorderThickness="0"/>
        <Button x:Name="LicYes" Content="동의하고 시작" Padding="14,7" Margin="4" Background="#4F9CF9" Foreground="White" FontWeight="Bold" BorderThickness="0" IsEnabled="False"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
    $LW = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $lx))
    $LW.FindName('LicText').Text = $text
    $chk = $LW.FindName('LicCheck'); $yes = $LW.FindName('LicYes'); $no = $LW.FindName('LicNo')
    $chk.Add_Checked({ $yes.IsEnabled = $true }); $chk.Add_Unchecked({ $yes.IsEnabled = $false })
    $yes.Add_Click({ $LW.DialogResult = $true; $LW.Close() })
    $no.Add_Click({ $LW.DialogResult = $false; $LW.Close() })
    $r = $LW.ShowDialog()
    if ($r -eq $true) { $script:Cfg.licenseAccepted = $script:LicenseVersion; Save-Config $script:Cfg; return $true }
    return $false
}

if ("$($script:Cfg.licenseAccepted)" -ne $script:LicenseVersion) {
    if (-not (Show-LicenseDialog)) { exit }
}
[void]$W.ShowDialog()
