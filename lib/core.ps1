# TailCraft core library - 다운로드 / 자바 / 서버 / 테일스케일 함수 모음
# Copyright (c) 2026 상덕. All rights reserved. 수정·재배포·복제 금지 — LICENSE.txt 참조.
# PowerShell 5.1 호환

$script:UA = 'TailCraft/1.0 (https://github.com/tailcraft)'
$script:TsExe = 'C:\Program Files\Tailscale\tailscale.exe'

function Get-TcRoot { return $global:TcRoot }

# ---------------- 설정 ----------------
function Get-DefaultConfig {
    return [ordered]@{
        firstRunDone   = $false
        loader         = 'paper'        # paper | fabric | neoforge | forge
        mcVersion      = ''
        loaderVersion  = ''             # paper: build 번호, fabric: loader, neoforge/forge: 버전
        installedKey   = ''             # loader-mc-loaderVersion (설치 완료 식별자)
        ramMB          = 4096
        port           = 25565
        maxPlayers     = 10
        onlineMode     = $true
        whitelist      = $false
        viewDistance   = 10
        difficulty     = 'normal'
        gamemode       = 'survival'
        motd           = 'TailCraft Server'
        extraJvmArgs   = ''
        autoStart      = $false
        eulaAccepted   = $false
        networkMode    = 'tailscale'    # tailscale | portforward | lan
        upnp           = $true          # portforward 모드에서 UPnP 자동 개방 시도
        tsShareLink    = ''             # 테일스케일 노드 공유 링크 (안내문에 포함)
        autoEssentials = $true          # 설치 시 EssentialsX(플러그인 지원 로더) / Fabric API 자동 설치
        customCmds     = @('list','tps','save-all')   # 콘솔 빠른 명령 (사용자 추가분)
        licenseAccepted = ''            # 동의한 EULA 버전
        lang           = ''            # 'ko' | 'en' (빈 값이면 최초 실행 시 선택)
    }
}

function Get-Config {
    $p = Join-Path (Get-TcRoot) 'config.json'
    $cfg = Get-DefaultConfig
    if (Test-Path $p) {
        try {
            $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $j.PSObject.Properties) { $cfg[$prop.Name] = $prop.Value }
        } catch {}
    }
    return $cfg
}

function Save-Config($cfg) {
    $p = Join-Path (Get-TcRoot) 'config.json'
    ($cfg | ConvertTo-Json -Depth 5) | Set-Content $p -Encoding UTF8
}

# ---------------- HTTP ----------------
function Invoke-TcJson($url) {
    return Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = $script:UA } -TimeoutSec 60
}
function Invoke-TcText($url) {
    return (Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = $script:UA } -TimeoutSec 60 -UseBasicParsing).Content
}
function Save-TcFile($url, $dest) {
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', $script:UA)
    $wc.DownloadFile($url, $dest)
    $wc.Dispose()
}

# ---------------- 버전 비교 ----------------
function ConvertTo-McVersionObj($v) {
    # "1.20.1" -> [version]1.20.1 / "1.21" -> 1.21.0 ; 스냅샷은 0.0.0
    if ($v -match '^(\d+)\.(\d+)(?:\.(\d+))?$') {
        $patch = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        return New-Object System.Version ([int]$Matches[1]), ([int]$Matches[2]), $patch
    }
    return New-Object System.Version 0, 0, 0
}
function Sort-McVersions($list) {
    return @($list | Where-Object { $_ -match '^\d+\.\d+(\.\d+)?$' } | Sort-Object { ConvertTo-McVersionObj $_ } -Descending)
}

# ---------------- 자바 ----------------
function Get-RequiredJava($mc) {
    $v = ConvertTo-McVersionObj $mc
    if ($v -ge (ConvertTo-McVersionObj '26.1'))   { return 25 }
    if ($v -ge (ConvertTo-McVersionObj '1.20.5')) { return 21 }
    if ($v -ge (ConvertTo-McVersionObj '1.17'))   { return 17 }
    return 8
}

function Get-JavaMajor($javaExe) {
    $ErrorActionPreference = 'Continue'
    try {
        $out = cmd /c "`"$javaExe`" -version 2>&1" | Out-String
        if ($out -match 'version "(\d+)(?:\.(\d+))?') {
            $maj = [int]$Matches[1]
            if ($maj -eq 1 -and $Matches[2]) { return [int]$Matches[2] }   # 1.8 -> 8
            return $maj
        }
    } catch {}
    return 0
}

function Find-Java($major) {
    # 1) 동봉 런타임
    $bundled = Join-Path (Get-TcRoot) "runtime\jre-$major"
    if (Test-Path $bundled) {
        $exe = Get-ChildItem -Path $bundled -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    # 2) JAVA_HOME
    if ($env:JAVA_HOME) {
        $exe = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if ((Test-Path $exe) -and ((Get-JavaMajor $exe) -eq $major)) { return $exe }
    }
    # 3) PATH
    $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($cmd -and ((Get-JavaMajor $cmd.Source) -eq $major)) { return $cmd.Source }
    # 4) 흔한 설치 경로
    foreach ($base in @("$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Java", "$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Zulu")) {
        if (Test-Path $base) {
            foreach ($d in Get-ChildItem $base -Directory -ErrorAction SilentlyContinue) {
                $exe = Join-Path $d.FullName 'bin\java.exe'
                if ((Test-Path $exe) -and ((Get-JavaMajor $exe) -eq $major)) { return $exe }
            }
        }
    }
    return $null
}

function Install-Java($major, [scriptblock]$Status) {
    $root = Get-TcRoot
    $dest = Join-Path $root "runtime\jre-$major"
    $zip  = Join-Path $root "runtime\jre-$major.zip"
    $url  = "https://api.adoptium.net/v3/binary/latest/$major/ga/windows/x64/jre/hotspot/normal/eclipse"
    if ($Status) { & $Status "Java $major 런타임 다운로드 중 (Adoptium)..." }
    Save-TcFile $url $zip
    if ($Status) { & $Status "Java $major 압축 해제 중..." }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    Remove-Item $zip -Force
    return (Find-Java $major)
}

# ---------------- 로더 성격 ----------------
function Test-PluginLoader($loader) { return ($loader -in 'paper','purpur','folia' -or $loader -like 'arclight-*') }
function Test-ModLoader($loader)    { return ($loader -eq 'fabric' -or $loader -in 'forge','neoforge' -or $loader -like 'arclight-*') }
function Get-ModrinthLoaders($loader, $kind) {
    # kind: 'mod' | 'plugin'
    if ($kind -eq 'plugin') { switch ($loader) { 'paper' { return @('paper','spigot','bukkit') } 'purpur' { return @('purpur','paper','spigot','bukkit') } 'folia' { return @('folia','paper') } default { return @('spigot','bukkit','paper') } } }
    switch -Wildcard ($loader) { '*fabric*' { return @('fabric') } '*neoforge*' { return @('neoforge') } '*forge*' { return @('forge') } default { return @() } }
}
function Get-ContentDir($loader, $kind) { return (Join-Path (Get-ServerDir) $(if ($kind -eq 'plugin') { 'plugins' } else { 'mods' })) }

$script:ArclightCache = $null
function Get-ArclightReleases {
    # 반환: 배열 of @{ Tag; Loader; Mc; Ver; Url; Name }
    if ($script:ArclightCache) { return $script:ArclightCache }
    $rel = Invoke-TcJson 'https://api.github.com/repos/IzzelAliz/Arclight/releases?per_page=100'
    $out = @()
    foreach ($r in $rel) {
        foreach ($a in $r.assets) {
            if ($a.name -match '^arclight-(fabric|forge|neoforge)-(\d+\.\d+(?:\.\d+)?)-([\w.\-]+?)(?:-[0-9a-f]{7})?\.jar$') {
                $out += @{ Tag = $r.tag_name; Loader = "arclight-$($Matches[1])"; Mc = $Matches[2]; Ver = $Matches[3]; Url = $a.browser_download_url; Name = $a.name; Pre = [bool]$r.prerelease }
            }
        }
    }
    $script:ArclightCache = $out
    return $out
}

# ---------------- 로더 버전 목록 ----------------
function Get-McVersions($loader) {
    if ($loader -like 'arclight-*') {
        $set = @{}; foreach ($r in (Get-ArclightReleases | Where-Object { $_.Loader -eq $loader })) { $set[$r.Mc] = $true }
        return Sort-McVersions @($set.Keys)
    }
    switch ($loader) {
        { $_ -in 'paper','folia' } {
            $j = Invoke-TcJson "https://fill.papermc.io/v3/projects/$loader"
            $all = @()
            foreach ($grp in $j.versions.PSObject.Properties) { $all += @($grp.Value) }
            return Sort-McVersions $all
        }
        'purpur' {
            $j = Invoke-TcJson 'https://api.purpurmc.org/v2/purpur'
            return Sort-McVersions @($j.versions)
        }
        'fabric' {
            $j = Invoke-TcJson 'https://meta.fabricmc.net/v2/versions/game'
            return Sort-McVersions @($j | Where-Object { $_.stable } | ForEach-Object { $_.version })
        }
        'neoforge' {
            $xml = [xml](Invoke-TcText 'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml')
            $set = @{}
            foreach ($v in $xml.metadata.versioning.versions.version) {
                if ($v -match '^(\d+)\.(\d+)\.(\d+)(\.\d+)?(-beta)?$') {
                    if ([int]$Matches[1] -ge 26) { $mc = "$($Matches[1]).$($Matches[2])"; if ([int]$Matches[3] -gt 0) { $mc += ".$($Matches[3])" } }
                    elseif ([int]$Matches[2] -eq 0) { $mc = "1.$($Matches[1])" } else { $mc = "1.$($Matches[1]).$($Matches[2])" }
                    $set[$mc] = $true
                }
            }
            return Sort-McVersions @($set.Keys)
        }
        'forge' {
            $j = Invoke-TcJson 'https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json'
            return Sort-McVersions @($j.PSObject.Properties.Name)
        }
    }
}

function Get-LoaderVersions($loader, $mc) {
    # 반환: 문자열 배열 (최신 우선). 첫 항목이 권장.
    if ($loader -like 'arclight-*') {
        $list = @(Get-ArclightReleases | Where-Object { $_.Loader -eq $loader -and $_.Mc -eq $mc } | Sort-Object { $_.Pre } | ForEach-Object { "$($_.Ver) [$($_.Tag)]" })
        return $list
    }
    switch ($loader) {
        { $_ -in 'paper','folia' } {
            $b = Invoke-TcJson "https://fill.papermc.io/v3/projects/$loader/versions/$mc/builds"
            $stable = @($b | Where-Object { $_.channel -eq 'STABLE' } | ForEach-Object { "$($_.id)" })
            if ($stable.Count -eq 0) { $stable = @($b | ForEach-Object { "$($_.id) ($($_.channel))" }) }
            return $stable
        }
        'purpur' {
            $j = Invoke-TcJson "https://api.purpurmc.org/v2/purpur/$mc"
            $list = @($j.builds.all); [array]::Reverse($list); return $list
        }
        'fabric' {
            $j = Invoke-TcJson "https://meta.fabricmc.net/v2/versions/loader/$mc"
            return @($j | ForEach-Object { $_.loader.version })
        }
        'neoforge' {
            $xml = [xml](Invoke-TcText 'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml')
            $parts = $mc.Split('.')
            if ([int]$parts[0] -ge 26) { $prefix = if ($parts.Count -ge 3) { "$mc." } else { "$mc.0." } }
            elseif ($parts.Count -ge 3) { $prefix = "$($parts[1]).$($parts[2])." } else { $prefix = "$($parts[1]).0." }
            $list = @($xml.metadata.versioning.versions.version | Where-Object { $_.StartsWith($prefix) })
            [array]::Reverse($list)
            return @($list)
        }
        'forge' {
            $j = Invoke-TcJson 'https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json'
            $list = @($j.$mc | ForEach-Object { $_ -replace "^$([regex]::Escape($mc))-", '' })
            [array]::Reverse($list)
            try {
                $promo = Invoke-TcJson 'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json'
                $rec = $promo.promos."$mc-recommended"
                if ($rec -and ($list -contains $rec)) { $list = @($rec) + @($list | Where-Object { $_ -ne $rec }) }
            } catch {}
            return $list
        }
    }
}

# ---------------- 서버 설치 ----------------
function Get-ServerDir { return (Join-Path (Get-TcRoot) 'server') }

function Install-Server($loader, $mc, $lv, [scriptblock]$Status) {
    $sdir = Get-ServerDir
    if (-not (Test-Path $sdir)) { New-Item -ItemType Directory -Path $sdir -Force | Out-Null }
    $javaMajor = Get-RequiredJava $mc
    $java = Find-Java $javaMajor
    if (-not $java) { $java = Install-Java $javaMajor $Status }
    if (-not $java) { throw "Java $javaMajor 준비에 실패했습니다." }

    if ($loader -like 'arclight-*') {
        $ver = ($lv -split ' ')[0]
        $r = Get-ArclightReleases | Where-Object { $_.Loader -eq $loader -and $_.Mc -eq $mc -and $_.Ver -eq $ver } | Select-Object -First 1
        if (-not $r) { throw "Arclight $loader $mc $ver 를 찾지 못했습니다." }
        if ($Status) { & $Status "Arclight 다운로드 중 ($($r.Name))..." }
        Save-TcFile $r.Url (Join-Path $sdir 'server.jar')
        foreach ($d in 'plugins','mods') { $dd = Join-Path $sdir $d; if (-not (Test-Path $dd)) { New-Item -ItemType Directory $dd -Force | Out-Null } }
        return $java
    }
    switch ($loader) {
        { $_ -in 'paper','folia' } {
            $build = ($lv -split ' ')[0]
            if ($Status) { & $Status "$loader $mc 빌드 $build 정보 조회..." }
            $b = Invoke-TcJson "https://fill.papermc.io/v3/projects/$loader/versions/$mc/builds/$build"
            $url = $b.downloads.'server:default'.url
            if (-not $url) { throw "$loader 다운로드 URL을 찾지 못했습니다." }
            if ($Status) { & $Status "$loader jar 다운로드 중..." }
            Save-TcFile $url (Join-Path $sdir 'server.jar')
        }
        'purpur' {
            $build = ($lv -split ' ')[0]
            if ($Status) { & $Status "Purpur $mc 빌드 $build 다운로드 중..." }
            Save-TcFile "https://api.purpurmc.org/v2/purpur/$mc/$build/download" (Join-Path $sdir 'server.jar')
        }
        'fabric' {
            $inst = (Invoke-TcJson 'https://meta.fabricmc.net/v2/versions/installer')[0].version
            $url = "https://meta.fabricmc.net/v2/versions/loader/$mc/$lv/$inst/server/jar"
            if ($Status) { & $Status "Fabric 서버 런처 다운로드 중..." }
            Save-TcFile $url (Join-Path $sdir 'server.jar')
        }
        'neoforge' {
            $url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$lv/neoforge-$lv-installer.jar"
            $inst = Join-Path $sdir 'installer.jar'
            if ($Status) { & $Status "NeoForge 인스톨러 다운로드 중..." }
            Save-TcFile $url $inst
            if ($Status) { & $Status "NeoForge 서버 설치 중 (수 분 소요)..." }
            $p = Start-Process -FilePath $java -ArgumentList @('-jar', "`"$inst`"", '--installServer', "`"$sdir`"") -WorkingDirectory $sdir -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -ne 0) { throw "NeoForge 설치 실패 (exit $($p.ExitCode))" }
            Remove-Item $inst -Force -ErrorAction SilentlyContinue
        }
        'forge' {
            $url = "https://maven.minecraftforge.net/net/minecraftforge/forge/$mc-$lv/forge-$mc-$lv-installer.jar"
            $inst = Join-Path $sdir 'installer.jar'
            if ($Status) { & $Status "Forge 인스톨러 다운로드 중..." }
            Save-TcFile $url $inst
            if ($Status) { & $Status "Forge 서버 설치 중 (수 분 소요)..." }
            $p = Start-Process -FilePath $java -ArgumentList @('-jar', "`"$inst`"", '--installServer', "`"$sdir`"") -WorkingDirectory $sdir -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -ne 0) { throw "Forge 설치 실패 (exit $($p.ExitCode))" }
            Remove-Item $inst -Force -ErrorAction SilentlyContinue
        }
    }
    return $java
}

function Get-LaunchArgs($cfg) {
    # 반환: @{ Java=...; Args=[string[]] }
    $sdir = Get-ServerDir
    $java = Find-Java (Get-RequiredJava $cfg.mcVersion)
    $enc = @('-Dfile.encoding=UTF-8','-Dstdout.encoding=UTF-8','-Dstderr.encoding=UTF-8','-Dsun.stdout.encoding=UTF-8','-Dsun.stderr.encoding=UTF-8')
    $mem = $enc + @("-Xms$([math]::Min(1024, [int]$cfg.ramMB))M", "-Xmx$([int]$cfg.ramMB)M")
    $extra = @()
    if ($cfg.extraJvmArgs) { $extra = @($cfg.extraJvmArgs -split '\s+' | Where-Object { $_ }) }
    $aikar = @('-XX:+UseG1GC','-XX:+ParallelRefProcEnabled','-XX:MaxGCPauseMillis=200','-XX:+UnlockExperimentalVMOptions','-XX:+DisableExplicitGC','-XX:G1NewSizePercent=30','-XX:G1MaxNewSizePercent=40','-XX:G1HeapRegionSize=8M','-XX:G1ReservePercent=20','-XX:InitiatingHeapOccupancyPercent=15')

    switch ($cfg.loader) {
        { $_ -in 'paper','purpur','folia','fabric' -or $_ -like 'arclight-*' } {
            return @{ Java = $java; Args = ($mem + $aikar + $extra + @('-jar', 'server.jar', 'nogui')) }
        }
        default {
            # (Neo)Forge: user_jvm_args.txt 에 메모리 기록, win_args.txt 사용
            $ujva = Join-Path $sdir 'user_jvm_args.txt'
            (($mem + $extra) -join "`r`n") | Set-Content $ujva -Encoding ASCII
            $winArgs = Get-ChildItem -Path (Join-Path $sdir 'libraries') -Recurse -Filter 'win_args.txt' -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($winArgs) {
                $rel = $winArgs.FullName.Substring($sdir.Length + 1)
                return @{ Java = $java; Args = @('@user_jvm_args.txt', "@$rel", 'nogui') }
            }
            # 구버전 포지: 단일 jar
            $jar = Get-ChildItem $sdir -Filter 'forge-*.jar' | Where-Object { $_.Name -notmatch 'installer' } | Select-Object -First 1
            if ($jar) { return @{ Java = $java; Args = ($mem + $extra + @('-jar', $jar.Name, 'nogui')) } }
            throw '서버 실행 파일을 찾지 못했습니다. 설정 탭에서 다시 설치하세요.'
        }
    }
}

# ---------------- server.properties ----------------
function Write-ServerProperties($cfg) {
    $sdir = Get-ServerDir
    if (-not (Test-Path $sdir)) { New-Item -ItemType Directory -Path $sdir -Force | Out-Null }
    $p = Join-Path $sdir 'server.properties'
    $lines = @()
    if (Test-Path $p) { $lines = Get-Content $p -Encoding UTF8 }
    $set = [ordered]@{
        'server-port'      = "$($cfg.port)"
        'max-players'      = "$($cfg.maxPlayers)"
        'online-mode'      = "$($cfg.onlineMode)".ToLower()
        'white-list'       = "$($cfg.whitelist)".ToLower()
        'view-distance'    = "$($cfg.viewDistance)"
        'difficulty'       = "$($cfg.difficulty)"
        'gamemode'         = "$($cfg.gamemode)"
        'motd'             = "$($cfg.motd)"
        'enable-query'     = 'false'
    }
    $out = New-Object System.Collections.Generic.List[string]
    $done = @{}
    foreach ($l in $lines) {
        if ($l -match '^\s*([^#=]+)=') {
            $k = $Matches[1].Trim()
            if ($set.Contains($k)) { $out.Add("$k=$($set[$k])"); $done[$k] = $true; continue }
        }
        $out.Add($l)
    }
    foreach ($k in $set.Keys) { if (-not $done[$k]) { $out.Add("$k=$($set[$k])") } }
    [IO.File]::WriteAllLines($p, [string[]]$out, (New-Object Text.UTF8Encoding $false))
}

function Write-Eula {
    $p = Join-Path (Get-ServerDir) 'eula.txt'
    "# Accepted via TailCraft launcher on $(Get-Date -Format s)`r`neula=true" | Set-Content $p -Encoding ASCII
}

# ---------------- 테일스케일 ----------------
function Test-TailscaleInstalled { return (Test-Path $script:TsExe) }

function Install-Tailscale([scriptblock]$Status) {
    $msi = Join-Path $env:TEMP 'tailscale-setup.msi'
    if ($Status) { & $Status '테일스케일 설치 파일 다운로드 중...' }
    Save-TcFile 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' $msi
    if ($Status) { & $Status '테일스케일 설치 중 (UAC 창이 뜨면 "예"를 누르세요)...' }
    $p = Start-Process msiexec.exe -ArgumentList @('/i', "`"$msi`"", '/quiet', '/norestart', 'TS_UNATTENDEDMODE=always') -Wait -PassThru -Verb RunAs
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "테일스케일 설치 실패 (exit $($p.ExitCode))" }
    Start-Sleep -Seconds 3
}

function Get-TailscaleStatus {
    # 반환: @{ Installed; State; IPv4; DNSName; Peers=[]; LoginName }
    $r = @{ Installed = $false; State = 'NotInstalled'; IPv4 = ''; DNSName = ''; Peers = @(); LoginName = '' }
    if (-not (Test-TailscaleInstalled)) { return $r }
    $r.Installed = $true
    try {
        $json = & $script:TsExe status --json 2>$null | Out-String
        if (-not $json) { $r.State = 'Stopped'; return $r }
        $s = $json | ConvertFrom-Json
        $r.State = $s.BackendState
        if ($s.Self) {
            $r.IPv4 = @($s.Self.TailscaleIPs | Where-Object { $_ -match '^\d+\.' })[0]
            $r.DNSName = "$($s.Self.DNSName)".TrimEnd('.')
        }
        if ($s.User -and $s.Self.UserID) {
            $u = $s.User."$($s.Self.UserID)"
            if ($u) { $r.LoginName = $u.LoginName }
        }
        if ($s.Peer) {
            $r.Peers = @($s.Peer.PSObject.Properties | ForEach-Object {
                $pp = $_.Value
                [pscustomobject]@{ Name = ("$($pp.DNSName)" -split '\.')[0]; Online = [bool]$pp.Online; IP = @($pp.TailscaleIPs)[0]; OS = $pp.OS }
            })
        }
    } catch { $r.State = 'Error' }
    return $r
}

function Start-TailscaleLogin {
    # tailscale up 을 백그라운드로 띄우고 로그인 URL 반환 (최대 20초 대기)
    $g = [guid]::NewGuid().ToString('N')
    $errFile = Join-Path $env:TEMP "tailcraft-ts-$g-err.txt"
    $outFile = Join-Path $env:TEMP "tailcraft-ts-$g-out.txt"
    Start-Process -FilePath $script:TsExe -ArgumentList @('up', '--unattended') -RedirectStandardError $errFile -RedirectStandardOutput $outFile -WindowStyle Hidden | Out-Null
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        foreach ($f in $errFile, $outFile) {
            if (Test-Path $f) {
                $t = Get-Content $f -Raw -ErrorAction SilentlyContinue
                if ($t -match '(https://login\.tailscale\.com/\S+)') { return $Matches[1] }
                if ($t -match '(?m)^Error: (.+)$') { throw $Matches[1] }
            }
        }
        $st = Get-TailscaleStatus
        if ($st.State -eq 'Running') { return 'already' }
    }
    return $null
}

function Add-FirewallRule($port) {
    $cmd = "netsh advfirewall firewall delete rule name=`"TailCraft Minecraft`" >nul & netsh advfirewall firewall add rule name=`"TailCraft Minecraft`" dir=in action=allow protocol=TCP localport=$port"
    Start-Process cmd.exe -ArgumentList @('/c', $cmd) -Verb RunAs -Wait -WindowStyle Hidden
}

function Test-FirewallRule($port) {
    $r = Get-NetFirewallRule -DisplayName 'TailCraft Minecraft' -ErrorAction SilentlyContinue
    if (-not $r) { return $false }
    return [bool](@($r | Get-NetFirewallPortFilter | Where-Object { "$($_.LocalPort)" -eq "$port" }).Count)
}

# ---------------- 포트포워딩 / LAN ----------------
function Get-LocalIPv4 {
    try {
        $r = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
        if ($r) { return @{ IP = "$(@($r.IPv4Address)[0].IPAddress)"; Gateway = "$(@($r.IPv4DefaultGateway)[0].NextHop)"; Adapter = "$($r.InterfaceAlias)" } }
    } catch {}
    return @{ IP = ''; Gateway = ''; Adapter = '' }
}

function Get-PublicIP {
    foreach ($u in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com')) {
        try { $t = (Invoke-TcText $u).Trim(); if ($t -match '^\d+\.\d+\.\d+\.\d+$') { return $t } } catch {}
    }
    return ''
}

function Add-UpnpMapping($port, $localIp) {
    # 공유기가 UPnP(IGD)를 켜둔 경우에만 성공. 반환: $true/$false
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $maps = $nat.StaticPortMappingCollection
        if ($null -eq $maps) { return $false }
        try { $maps.Remove($port, 'TCP') } catch {}
        $maps.Add($port, 'TCP', $port, $localIp, $true, 'TailCraft Minecraft') | Out-Null
        return $true
    } catch { return $false }
}

function Remove-UpnpMapping($port) {
    try { (New-Object -ComObject HNetCfg.NATUPnP).StaticPortMappingCollection.Remove($port, 'TCP') } catch {}
}

function Test-UpnpMapping($port) {
    try {
        $maps = (New-Object -ComObject HNetCfg.NATUPnP).StaticPortMappingCollection
        if ($null -eq $maps) { return $false }
        foreach ($m in $maps) { if ($m.ExternalPort -eq $port -and $m.Protocol -eq 'TCP') { return $true } }
    } catch {}
    return $false
}

function Open-PortChecker($port) {
    # 외부 포트 확인 사이트를 브라우저로 연다 (서버가 켜져 있어야 의미 있음)
    Start-Process "https://portchecker.co/check?port=$port"
}

# ---------------- Modrinth ----------------
function ConvertTo-JsonArrayParam($arr) { return [uri]::EscapeDataString(('[' + (($arr | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']')) }

function Search-Modrinth($query, $loader, $mc, $kind, $limit = 20) {
    $ptype = if ($kind -eq 'plugin') { 'plugin' } else { 'mod' }
    $facets = @("[`"project_type:$ptype`"]")
    if ($mc -and $kind -ne 'plugin') { $facets += "[`"versions:$mc`"]" }   # 플러그인은 대표 버전만 태그하는 경우가 많아 버전 필터 생략
    $ld = Get-ModrinthLoaders $loader $kind
    if ($ld.Count -gt 0) { $facets += ('[' + (($ld | ForEach-Object { "`"categories:$_`"" }) -join ',') + ']') }
    $f = [uri]::EscapeDataString('[' + ($facets -join ',') + ']')
    $url = "https://api.modrinth.com/v2/search?query=$([uri]::EscapeDataString($query))&limit=$limit&index=relevance&facets=$f"
    $r = Invoke-TcJson $url
    return @($r.hits | ForEach-Object { [pscustomobject]@{ Slug = $_.slug; Title = $_.title; Desc = $_.description; Downloads = $_.downloads; Id = $_.project_id } })
}

function Get-ModrinthBestVersion($slug, $loader, $mc, $kind) {
    $ld = Get-ModrinthLoaders $loader $kind
    $base = "https://api.modrinth.com/v2/project/$slug/version"
    $lq = if ($ld.Count -gt 0) { "loaders=$(ConvertTo-JsonArrayParam $ld)" } else { '' }
    # 1) 정확히 일치
    $vs = @(Invoke-TcJson ("$base`?game_versions=$(ConvertTo-JsonArrayParam @($mc))" + $(if ($lq) { "&$lq" } else { '' })))
    if ($vs.Count -eq 0 -and $kind -eq 'plugin') {
        # 2) 플러그인은 하위 호환: 같은 1.21.x 계열 → 3) 그 이하 아무 버전 중 최신
        $all = @(Invoke-TcJson ("$base" + $(if ($lq) { "?$lq" } else { '' })))
        $t = ConvertTo-McVersionObj $mc
        $sameMinor = @($all | Where-Object { $gv = $_.game_versions; @($gv | Where-Object { $o = ConvertTo-McVersionObj $_; $o.Major -eq $t.Major -and $o.Minor -eq $t.Minor }).Count -gt 0 })
        if ($sameMinor.Count -gt 0) { $vs = $sameMinor }
        else { $vs = @($all | Where-Object { @($_.game_versions | Where-Object { (ConvertTo-McVersionObj $_) -le $t -and (ConvertTo-McVersionObj $_).Major -gt 0 }).Count -gt 0 }) }
    }
    if ($vs.Count -eq 0) { return $null }
    $v = @($vs | Where-Object { $_.version_type -eq 'release' })[0]; if (-not $v) { $v = $vs[0] }
    $file = @($v.files | Where-Object { $_.primary })[0]; if (-not $file) { $file = $v.files[0] }
    return @{ Version = $v.version_number; Url = $file.url; FileName = $file.filename; Deps = @($v.dependencies | Where-Object { $_.dependency_type -eq 'required' -and $_.project_id } | ForEach-Object { $_.project_id }) }
}

function Install-ModrinthProject($slug, $loader, $mc, $kind, [scriptblock]$Status, $depth = 0) {
    # 반환: 설치된 파일명 배열 (필수 의존성 포함)
    $dir = Get-ContentDir $loader $kind
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
    $v = Get-ModrinthBestVersion $slug $loader $mc $kind
    if (-not $v) { throw "'$slug' 에 $mc / $loader 호환 버전이 없습니다." }
    $done = @()
    $existing = Get-ChildItem $dir -Filter '*.jar*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $v.FileName -or $_.Name -eq "$($v.FileName).disabled" }
    if (-not $existing) {
        if ($Status) { & $Status "다운로드: $($v.FileName)" }
        Save-TcFile $v.Url (Join-Path $dir $v.FileName)
    }
    $done += $v.FileName
    if ($depth -lt 3) {
        foreach ($pid in $v.Deps) { try { $done += Install-ModrinthProject $pid $loader $mc $kind $Status ($depth + 1) } catch {} }
    }
    return $done
}

function Get-RecommendedSet($loader) {
    # 반환: 배열 of @{ Slug; Kind; Title; Default; Note }
    $set = @()
    if ($loader -eq 'folia') {
        $set += @{ Slug = 'chunky'; Kind = 'plugin'; Title = 'Chunky'; Default = $false; Note = '월드 미리 생성으로 렉 감소 (Folia 호환)' }
        return $set
    }
    if (Test-PluginLoader $loader) {
        $set += @{ Slug = 'essentialsx'; Kind = 'plugin'; Title = 'EssentialsX'; Default = $true;  Note = '홈/워프/킷/TPA/경제/채팅 — 서버 필수 플러그인' }
        $set += @{ Slug = 'luckperms';   Kind = 'plugin'; Title = 'LuckPerms';   Default = $false; Note = '권한 관리 (EssentialsX 명령 권한 세분화)' }
        $set += @{ Slug = 'chunky';      Kind = 'plugin'; Title = 'Chunky';      Default = $false; Note = '월드 미리 생성으로 렉 감소' }
    }
    if ($loader -like '*fabric*') {
        $set += @{ Slug = 'fabric-api'; Kind = 'mod'; Title = 'Fabric API'; Default = $true;  Note = '대부분의 Fabric 모드가 요구하는 기본 라이브러리' }
        $set += @{ Slug = 'lithium';    Kind = 'mod'; Title = 'Lithium';    Default = $false; Note = '서버 최적화 (클라이언트 설치 불필요)' }
        if ($loader -eq 'fabric') { $set += @{ Slug = 'essential-commands'; Kind = 'mod'; Title = 'Essential Commands'; Default = $false; Note = 'Fabric용 홈/워프/TPA/스폰 (EssentialsX 대체)' } }
    }
    if ($loader -in 'forge','neoforge') {
        $set += @{ Slug = 'ftb-essentials'; Kind = 'mod'; Title = 'FTB Essentials'; Default = $false; Note = '홈/워프/TPA/킥/밴 등 (EssentialsX 대체, FTB Library 자동 포함)' }
    }
    return $set
}

# ---------------- jar 메타데이터 ----------------
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
function Get-JarInfo($path) {
    $info = @{ Name = [IO.Path]::GetFileNameWithoutExtension(($path -replace '\.disabled$','')); Version = ''; Id = ''; Type = '' }
    try {
        $z = [IO.Compression.ZipFile]::OpenRead($path)
        try {
            $get = { param($n) $e = $z.GetEntry($n); if ($e) { $sr = New-Object IO.StreamReader($e.Open()); $t = $sr.ReadToEnd(); $sr.Dispose(); return $t }; return $null }
            $t = & $get 'fabric.mod.json'
            if ($t) { $j = $t | ConvertFrom-Json; $info.Name = "$($j.name)"; $info.Version = "$($j.version)"; $info.Id = "$($j.id)"; $info.Type = 'Fabric 모드'; return $info }
            $t = & $get 'META-INF/neoforge.mods.toml'; if (-not $t) { $t = & $get 'META-INF/mods.toml' }
            if ($t) {
                if ($t -match '(?m)^\s*modId\s*=\s*"([^"]+)"') { $info.Id = $Matches[1] }
                if ($t -match '(?m)^\s*displayName\s*=\s*"([^"]+)"') { $info.Name = $Matches[1] }
                if ($t -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $info.Version = $Matches[1] }
                if ($info.Version -like '*jarVersion*') { $m = & $get 'META-INF/MANIFEST.MF'; if ($m -and $m -match 'Implementation-Version:\s*(\S+)') { $info.Version = $Matches[1] } else { $info.Version = '' } }
                $info.Type = if ($z.GetEntry('META-INF/neoforge.mods.toml')) { 'NeoForge 모드' } else { 'Forge 모드' }; return $info
            }
            $t = & $get 'paper-plugin.yml'; if (-not $t) { $t = & $get 'plugin.yml' }
            if ($t) {
                if ($t -match '(?m)^name:\s*(.+)$') { $info.Name = $Matches[1].Trim().Trim('"',"'") }
                if ($t -match '(?m)^version:\s*(.+)$') { $info.Version = $Matches[1].Trim().Trim('"',"'") }
                if ($t -match '(?m)^main:\s*(.+)$') { $info.Id = $Matches[1].Trim() }
                $info.Type = 'Bukkit 플러그인'; return $info
            }
        } finally { $z.Dispose() }
    } catch {}
    return $info
}

function Get-ContentList($loader, $kind) {
    $dir = Get-ContentDir $loader $kind
    if (-not (Test-Path $dir)) { return @() }
    $out = @()
    foreach ($f in (Get-ChildItem $dir -File | Where-Object { $_.Name -match '\.jar(\.disabled)?$' } | Sort-Object Name)) {
        $i = Get-JarInfo $f.FullName
        $out += [pscustomobject]@{ Enabled = $(if ($f.Name -like '*.disabled') { '' } else { '✔' }); Name = $i.Name; Version = $i.Version; Id = $i.Id; Type = $i.Type; File = $f.Name; SizeMB = [math]::Round($f.Length / 1MB, 2); Path = $f.FullName }
    }
    return $out
}

function Export-ModPack($loader, $dest) {
    $dir = Get-ContentDir $loader 'mod'
    if (-not (Test-Path $dir)) { throw 'mods 폴더가 없습니다.' }
    if (Test-Path $dest) { Remove-Item $dest -Force }
    $tmp = Join-Path $env:TEMP ("tcmods-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
    Get-ChildItem $dir -Filter '*.jar' | Copy-Item -Destination $tmp
    "친구용 모드 묶음`r`n서버 로더: $loader`r`n이 폴더의 jar 들을 자기 마인크래프트의 mods 폴더(%appdata%\.minecraft\mods 또는 사용하는 런처의 인스턴스 mods 폴더)에 넣고, 같은 로더/버전으로 실행하세요.`r`n서버 전용 최적화 모드(lithium 등)는 넣어도 무방합니다." | Set-Content (Join-Path $tmp 'README.txt') -Encoding UTF8
    [IO.Compression.ZipFile]::CreateFromDirectory($tmp, $dest)
    Remove-Item $tmp -Recurse -Force
}

# ---------------- 진단 ----------------
function Get-PortOwner($port) {
    try { $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $pr = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; return "PID $($c.OwningProcess) $($pr.ProcessName)" } } catch {}
    return ''
}

# ---------------- 유틸 ----------------
function Get-FolderSizeMB($path) {
    if (-not (Test-Path $path)) { return 0 }
    $s = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return [math]::Round(($s / 1MB), 1)
}

function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    return @{
        TotalRamMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
        FreeRamMB  = [math]::Round($os.FreePhysicalMemory / 1KB)
        Cores      = [int]$cs.NumberOfLogicalProcessors
        HostName   = $env:COMPUTERNAME
    }
}
