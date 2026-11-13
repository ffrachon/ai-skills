<#
.SYNOPSIS
  Read-only audit of a Windows PC used for heavy development work.

.DESCRIPTION
  Reports Dev Drive status, Defender state, where toolchains and caches live, Windows Search
  scope, power plan, page file, free disk, build-output folder sizes, WSL/container disk
  placement and .wslconfig caps, Smart App Control / memory integrity state (report only),
  global git settings, Gradle cache settings and PostgreSQL services.

  This script ONLY READS. It changes no setting, exclusion, file or registry value.
  Run it from a normal PowerShell; run it from an admin PowerShell to also see Defender
  exclusions and per-volume Dev Drive details (otherwise those report "needs admin").

  Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER DevRoot
  One or more folders where projects live. Default: auto-detect (Dev Drive / ReFS volume
  roots and common folders under the user profile).

.PARAMETER MaxDepth
  How deep to look for build-output folders under each DevRoot (default 5).

.PARAMETER SkipSizes
  Skip measuring folder sizes (the slowest part on large trees).

.PARAMETER Json
  Print the results as JSON instead of text.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\audit.ps1
  powershell -ExecutionPolicy Bypass -File .\audit.ps1 -DevRoot D:\src -Json
#>
[CmdletBinding()]
param(
    [string[]]$DevRoot,
    [int]$MaxDepth = 5,
    [switch]$SkipSizes,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
$NeedsAdmin = 'needs admin (rerun from an admin PowerShell to see this)'

# ---------------------------------------------------------------- helpers

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Size([double]$bytes) {
    if ($bytes -lt 0) { return 'n/a' }
    if ($bytes -ge 1TB) { return ('{0:N1} TB' -f ($bytes / 1TB)) }
    if ($bytes -ge 1GB) { return ('{0:N1} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N0} MB' -f ($bytes / 1MB)) }
    return ('{0:N0} KB' -f ($bytes / 1KB))
}

# Folder size via robocopy in list-only mode (/L copies nothing). Much faster than
# Get-ChildItem on trees with millions of files; skips junctions (/XJ).
function Get-DirSize([string]$path) {
    if ($SkipSizes) { return -1 }
    if (-not (Test-Path -LiteralPath $path)) { return -1 }
    try {
        $out = & robocopy.exe $path 'NULL-audit-no-copy' /L /S /NJH /BYTES /NFL /NDL /XJ /R:0 /W:0 /NP 2>$null
        # Summary rows are Dirs, Files, Bytes (labels are localized, order is not).
        $rows = @($out | Where-Object { $_ -match '^\s*[^:]+:\s+\d+\s+\d+' })
        if ($rows.Count -ge 3 -and $rows[2] -match ':\s+(\d+)') { return [double]$Matches[1] }
    } catch { }
    try {
        $sum = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [double]$sum
    } catch { return -1 }
}

$script:Volumes = @()
function Get-VolumeInfo([string]$path) {
    if (-not $path) { return $null }
    try { $full = [IO.Path]::GetFullPath($path) } catch { return $null }
    if ($full.Length -lt 2 -or $full[1] -ne ':') { return $null }
    $letter = $full.Substring(0, 1).ToUpper()
    return $script:Volumes | Where-Object { $_.Drive -eq $letter } | Select-Object -First 1
}

$script:Findings = New-Object System.Collections.ArrayList
function Add-Finding([string]$level, [string]$area, [string]$text) {
    [void]$script:Findings.Add([pscustomobject]@{ Level = $level; Area = $area; Text = $text })
}

$IsAdmin = Test-IsAdmin
$result = [ordered]@{ GeneratedAt = (Get-Date).ToString('s'); RunAsAdmin = $IsAdmin }

# ---------------------------------------------------------------- system

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cs = Get-CimInstance Win32_ComputerSystem
    $result.System = [ordered]@{
        OS        = "$($os.Caption) build $($os.BuildNumber)"
        CPU       = ($cpu.Name -replace '\s+', ' ').Trim()
        Cores     = $cpu.NumberOfCores
        Threads   = $cpu.NumberOfLogicalProcessors
        RAM       = Format-Size ([double]$cs.TotalPhysicalMemory)
        HasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    }
    $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    if ($pf.Count -gt 0) {
        $result.System.PageFile = (($pf | ForEach-Object { "$($_.Name) $(Format-Size ([double]$_.AllocatedBaseSize * 1MB)), peak use $(Format-Size ([double]$_.PeakUsage * 1MB))" }) -join '; ') +
            $(if ($cs.AutomaticManagedPagefile) { ' (system-managed)' } else { ' (manual size)' })
    } else {
        $result.System.PageFile = 'none'
        Add-Finding 'warn' 'Memory' 'No page file. Memory peaks during parallel builds then fail instead of paging; a system-managed page file on the fastest SSD is the safe default (references/windows-extras.md).'
    }
    if ([int]$os.BuildNumber -lt 22621) {
        Add-Finding 'info' 'Dev Drive' 'Dev Drive needs Windows 11 22H2 (build 22621) or later; this build is older.'
    }
} catch { $result.System = "error: $($_.Exception.Message)" }

# ---------------------------------------------------------------- volumes and Dev Drive

$devDriveGlobal = (& fsutil.exe devdrv query 2>&1 | Out-String).Trim()
$vols = @()
try {
    $vols = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter
} catch { }
foreach ($v in $vols) {
    $letter = [string]$v.DriveLetter
    $dd = 'not ReFS'
    if ($v.FileSystem -eq 'ReFS') {
        $q = (& fsutil.exe devdrv query "${letter}:" 2>&1 | Out-String).Trim()
        if ($q -match 'Error 5|Access is denied') { $dd = "ReFS; Dev Drive details $NeedsAdmin" }
        elseif ($q -match 'not a developer volume') { $dd = 'ReFS, but not a Dev Drive' }
        else { $dd = ($q -replace '\s*\r?\n\s*', '; ') }
    }
    $freePct = if ($v.Size) { [math]::Round(100 * $v.SizeRemaining / $v.Size, 0) } else { 0 }
    $script:Volumes += [pscustomobject]@{
        Drive      = $letter
        Label      = $v.FileSystemLabel
        FileSystem = $v.FileSystem
        Size       = Format-Size ([double]$v.Size)
        Free       = Format-Size ([double]$v.SizeRemaining)
        FreePct    = $freePct
        DevDrive   = $dd
        IsReFS     = ($v.FileSystem -eq 'ReFS')
    }
    if ($freePct -lt 15) {
        Add-Finding 'suggest' 'Disk' "Drive ${letter}: has only $freePct% free ($(Format-Size ([double]$v.SizeRemaining))). Builds slow down and fail when a drive fills; see references/cleanup.md."
    }
}
$result.DevDriveGlobal = $devDriveGlobal
$result.Volumes = $script:Volumes
$refsVols = @($script:Volumes | Where-Object IsReFS)
if ($refsVols.Count -eq 0) {
    Add-Finding 'suggest' 'Dev Drive' 'No ReFS / Dev Drive volume found. A Dev Drive for code, caches and build output is usually the biggest safe win; see references/dev-drive.md.'
}

# ---------------------------------------------------------------- Defender

$def = [ordered]@{}
try {
    $st = Get-MpComputerStatus -ErrorAction Stop
    $def.AntivirusEnabled = $st.AntivirusEnabled
    $def.RealTimeProtection = $st.RealTimeProtectionEnabled
    $def.RunningMode = $st.AMRunningMode
    $def.TamperProtected = $st.IsTamperProtected
    $def.PlatformVersion = $st.AMProductVersion
    if (-not $st.RealTimeProtectionEnabled -and $st.AMRunningMode -eq 'Normal') {
        Add-Finding 'warn' 'Defender' 'Real-time protection is OFF. Turning it off is not a tuning step; switch it back on and use the measured options in references/defender.md instead.'
    }
} catch { $def.Status = "Defender status not available ($($_.Exception.Message)); another antivirus may be active." }
try {
    $pref = Get-MpPreference -ErrorAction Stop
    $pm = $pref.PerformanceModeStatus
    $def.PerformanceModeStatus = if ($null -eq $pm) { 'not reported (older Defender platform)' } elseif ("$pm" -eq '0') { '0 (enabled)' } elseif ("$pm" -eq '1') { '1 (disabled)' } else { "$pm" }
    if ("$pm" -eq '1') {
        Add-Finding 'suggest' 'Defender' 'Defender performance mode (asynchronous scanning on trusted Dev Drives) is disabled. See references/defender.md.'
    }
    $excl = @($pref.ExclusionPath)
    if ($excl.Count -gt 0 -and "$($excl[0])" -like 'N/A*') {
        $def.ExclusionPath = $NeedsAdmin
        $def.ExclusionProcess = $NeedsAdmin
        $def.ExclusionExtension = $NeedsAdmin
    } else {
        $def.ExclusionPath = @($pref.ExclusionPath | Where-Object { $_ })
        $def.ExclusionProcess = @($pref.ExclusionProcess | Where-Object { $_ })
        $def.ExclusionExtension = @($pref.ExclusionExtension | Where-Object { $_ })
        $risky = @(
            @{ P = $env:TEMP; Why = 'TEMP (installers and downloads unpack here)' },
            @{ P = $env:TMP; Why = 'TMP (installers and downloads unpack here)' },
            @{ P = $env:USERPROFILE; Why = 'the whole user profile' },
            @{ P = (Join-Path $env:USERPROFILE 'Downloads'); Why = 'Downloads' },
            @{ P = "$env:SystemDrive\"; Why = 'the whole system drive' },
            @{ P = $env:SystemRoot; Why = 'the Windows folder' }
        )
        foreach ($e in $def.ExclusionPath) {
            # contextual exclusions look like 'D:\src\:{ScanTrigger:OnAccess}'
            $en = (([string]$e) -replace '\\?:\{[^}]*\}$', '').TrimEnd('\')
            foreach ($r in $risky) {
                if ($r.P -and $en -ieq ([string]$r.P).TrimEnd('\')) {
                    Add-Finding 'warn' 'Defender' "Exclusion '$e' covers $($r.Why). This is a real security gap; see references/defender.md for safer alternatives."
                }
            }
            if ($en -match '^[A-Za-z]:$') {
                Add-Finding 'info' 'Defender' "Whole drive '$e' is excluded. Fine as an informed choice if downloads and installers stay off it; see the compensating habits in references/defender.md."
            }
            if ([string]$e -notmatch ':\{[^}]*\}$') {
                $plainCount = 1 + [int]$def['PlainExclusionCount']
                $def['PlainExclusionCount'] = $plainCount
            }
        }
        if ([int]$def['PlainExclusionCount'] -gt 0) {
            Add-Finding 'info' 'Defender' "$($def['PlainExclusionCount']) path exclusion(s) apply to every scan type, so even custom scans skip them. Adding '\:{ScanTrigger:OnAccess}' limits an exclusion to real-time scanning (references/defender.md)."
        }
    }
} catch { $def.Preferences = "not available ($($_.Exception.Message))" }
try {
    $av = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
    $def.RegisteredAntivirus = @($av | ForEach-Object { $_.displayName })
    $other = @($def.RegisteredAntivirus | Where-Object { $_ -and $_ -notmatch 'Defender' })
    if ($other.Count -gt 0) {
        Add-Finding 'info' 'Antivirus' ("Another antivirus is registered: " + ($other -join ', ') + ". Defender steps (performance mode, exclusions) may not apply; use that product's own tools (references/defender.md, last section).")
    }
} catch { }
$result.Defender = $def

# ---------------------------------------------------------------- other security features (report only)

$sec = [ordered]@{}
try {
    $sac = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction Stop).VerifiedAndReputablePolicyState
    $sec.SmartAppControl = switch ([int]$sac) { 0 { 'Off' } 1 { 'On' } 2 { 'Evaluation' } default { "unknown ($sac)" } }
    if ([int]$sac -eq 1) {
        Add-Finding 'info' 'Security' 'Smart App Control is On: it checks every new executable, including freshly built test binaries. If builds are blocked or slow to start, see references/windows-extras.md (a user decision).'
    }
} catch { $sec.SmartAppControl = 'not reported (older Windows or not available)' }
try {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
    $vbs = switch ([int]$dg.VirtualizationBasedSecurityStatus) { 0 { 'off' } 1 { 'enabled, not running' } 2 { 'running' } default { "$($dg.VirtualizationBasedSecurityStatus)" } }
    $sec.VirtualizationBasedSecurity = $vbs
    $sec.MemoryIntegrityHVCI = if (@($dg.SecurityServicesRunning) -contains 2) { 'running' } else { 'not running' }
} catch { $sec.VirtualizationBasedSecurity = "not readable ($($_.Exception.Message))" }
$result.SecurityFeatures = $sec

# ---------------------------------------------------------------- toolchains and caches

function Get-CmdOutput([string]$exe, [string[]]$argList) {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { return $null }
    try { return ((& $exe @argList 2>$null) | Select-Object -First 1) } catch { return $null }
}

$loc = [ordered]@{}
$loc.'RUSTUP_HOME (rustup toolchains)' = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { Join-Path $env:USERPROFILE '.rustup' }
$loc.'CARGO_HOME (cargo registry, git deps, tools)' = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
if ($env:CARGO_TARGET_DIR) { $loc.'CARGO_TARGET_DIR (shared target)' = $env:CARGO_TARGET_DIR }
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) { $loc.'Flutter SDK' = Split-Path (Split-Path $flutterCmd.Source -Parent) -Parent }
elseif ($env:FLUTTER_ROOT) { $loc.'Flutter SDK' = $env:FLUTTER_ROOT }
$loc.'PUB_CACHE (Dart/Flutter packages)' = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
$npmCache = Get-CmdOutput 'npm' @('config', 'get', 'cache')
if ($npmCache) { $loc.'npm cache' = $npmCache }
$pnpmStore = Get-CmdOutput 'pnpm' @('store', 'path')
if ($pnpmStore) { $loc.'pnpm store' = $pnpmStore }
$loc.'GRADLE_USER_HOME (Android builds)' = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
if ($env:NUGET_PACKAGES) { $loc.'NUGET_PACKAGES' = $env:NUGET_PACKAGES }
if ($env:PIP_CACHE_DIR) { $loc.'PIP_CACHE_DIR' = $env:PIP_CACHE_DIR }
$loc.'TEMP (this process)' = $env:TEMP
$loc.'TMP (this process)' = $env:TMP
$userTemp = [Environment]::GetEnvironmentVariable('TEMP', 'User')
if ($userTemp) { $loc.'TEMP (user setting, unexpanded)' = $userTemp }
$sccache = Get-Command sccache -ErrorAction SilentlyContinue
if ($env:RUSTC_WRAPPER) { $loc.'RUSTC_WRAPPER' = $env:RUSTC_WRAPPER }

$toolRows = @()
foreach ($k in $loc.Keys) {
    $p = [Environment]::ExpandEnvironmentVariables([string]$loc[$k])
    $exists = Test-Path -LiteralPath $p
    $vi = Get-VolumeInfo $p
    $toolRows += [pscustomobject]@{
        What   = $k
        Path   = $p
        Exists = $exists
        Drive  = if ($vi) { "$($vi.Drive): $($vi.FileSystem)" } else { '?' }
        Size   = if ($exists -and $k -ne 'RUSTC_WRAPPER') { Format-Size (Get-DirSize $p) } else { '' }
    }
}
$result.ToolchainsAndCaches = $toolRows
$result.Sccache = if ($sccache) { $sccache.Source } else { 'not installed' }

if ($refsVols.Count -gt 0) {
    $onC = @($toolRows | Where-Object { $_.Exists -and $_.Drive -like "$($env:SystemDrive.TrimEnd(':')):*" -and $_.What -ne 'RUSTC_WRAPPER' -and $_.What -notlike '*user setting*' })
    if ($onC.Count -gt 0) {
        Add-Finding 'suggest' 'Caches' ("A ReFS / Dev Drive volume exists, but these still live on the system drive: " + (($onC | ForEach-Object { $_.What -replace ' \(.*', '' }) -join ', ') + '. Moving package caches (and, for heavy test suites, build temp files) to the Dev Drive is the documented use; see references/dev-drive.md and references/temp-files.md.')
    }
}

# Cargo config: linker / temp settings (global config only; project configs are per repo)
$cargoHome = [Environment]::ExpandEnvironmentVariables([string]$loc.'CARGO_HOME (cargo registry, git deps, tools)')
foreach ($cfgName in @('config.toml', 'config')) {
    $cfg = Join-Path $cargoHome $cfgName
    if (Test-Path -LiteralPath $cfg) {
        $txt = Get-Content -LiteralPath $cfg -Raw -ErrorAction SilentlyContinue
        $result.CargoGlobalConfig = [ordered]@{
            Path        = $cfg
            SetsLinker  = [bool]($txt -match '(?m)^\s*linker\s*=')
            SetsEnv     = [bool]($txt -match '(?m)^\s*\[env\]')
            SetsWrapper = [bool]($txt -match '(?m)rustc-wrapper')
        }
        break
    }
}

# ---------------------------------------------------------------- Windows Search

$search = [ordered]@{}
try {
    $svc = Get-Service WSearch -ErrorAction Stop
    $search.Service = "$($svc.Status) (start: $($svc.StartType))"
} catch { $search.Service = 'not installed' }
$rulesKey = 'HKLM:\SOFTWARE\Microsoft\Windows Search\CrawlScopeManager\Windows\SystemIndex\WorkingSetRules'
$included = @()
try {
    foreach ($r in (Get-ChildItem $rulesKey -ErrorAction Stop)) {
        $ip = Get-ItemProperty $r.PSPath
        if ($ip.Include -eq 1 -and $ip.URL -match '^file:///([A-Za-z]):\\(?:\[[^\]]+\]\\)?(.*)$') {
            $included += ("{0}:\{1}" -f $Matches[1].ToUpper(), $Matches[2])
        }
    }
    $search.IndexedFolders = $included
} catch { $search.IndexedFolders = 'could not read index scope' }
$dataVols = @($script:Volumes | Where-Object { $_.Drive -ne $env:SystemDrive.TrimEnd(':') })
$perDrive = @()
foreach ($dv in $dataVols) {
    $hit = @($included | Where-Object { $_ -like "$($dv.Drive):*" })
    $rootAttr = ''
    try { $rootAttr = (Get-Item -LiteralPath "$($dv.Drive):\" -Force).Attributes.ToString() } catch { }
    $perDrive += [pscustomobject]@{
        Drive              = "$($dv.Drive):"
        InIndexScope       = ($hit.Count -gt 0)
        RootNotContentIndexed = ($rootAttr -match 'NotContentIndexed')
    }
}
$search.DataDrives = $perDrive
$result.WindowsSearch = $search
foreach ($pd in $perDrive) {
    if (-not $pd.InIndexScope) {
        Add-Finding 'info' 'Indexing' "Drive $($pd.Drive) is not in the Windows Search scope, so unticking 'Allow files on this drive to have contents indexed' would gain nothing there (see references/indexing.md)."
    }
}

# ---------------------------------------------------------------- power

try {
    $scheme = (& powercfg.exe /getactivescheme 2>$null | Out-String).Trim()
    $result.PowerPlan = $scheme
    if ($scheme -match '\((.+)\)\s*$' -and $Matches[1] -match 'saver|economy|economie') {
        Add-Finding 'suggest' 'Power' "Active power plan looks like a power saver plan: $($Matches[1])."
    }
} catch { $result.PowerPlan = 'unknown' }

# ---------------------------------------------------------------- WSL / containers

$wsl = @()
try {
    foreach ($k in (Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop)) {
        $ip = Get-ItemProperty $k.PSPath
        if (-not $ip.DistributionName) { continue }
        $base = [string]$ip.BasePath
        if ($base.StartsWith('\\?\')) { $base = $base.Substring(4) }
        $vhd = $null
        if ($ip.VhdFileName) { $vhd = Join-Path $base $ip.VhdFileName } else { $vhd = Join-Path $base 'ext4.vhdx' }
        $size = if (Test-Path -LiteralPath $vhd) { Format-Size ((Get-Item -LiteralPath $vhd -Force).Length) } else { 'vhdx not found' }
        $vi = Get-VolumeInfo $base
        $bytes = if (Test-Path -LiteralPath $vhd) { [double](Get-Item -LiteralPath $vhd -Force).Length } else { 0 }
        $wsl += [pscustomobject]@{
            Distro = $ip.DistributionName
            Disk   = $vhd
            Drive  = if ($vi) { "$($vi.Drive): $($vi.FileSystem)" } else { '?' }
            Size   = $size
            Bytes  = $bytes
        }
    }
} catch { }
$dockerData = Join-Path $env:LOCALAPPDATA 'Docker\wsl'
if (Test-Path -LiteralPath $dockerData) {
    Get-ChildItem -LiteralPath $dockerData -Recurse -Filter *.vhdx -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $wsl += [pscustomobject]@{ Distro = 'Docker Desktop data'; Disk = $_.FullName; Drive = "$((Get-VolumeInfo $_.FullName).Drive):"; Size = Format-Size $_.Length; Bytes = [double]$_.Length }
    }
}
$result.WslAndContainerDisks = @($wsl | Select-Object Distro, Drive, Size, Disk)
$bigWsl = @($wsl | Where-Object { $_.Drive -like "$($env:SystemDrive.TrimEnd(':')):*" -and $_.Bytes -ge 20GB })
foreach ($b in $bigWsl) {
    Add-Finding 'info' 'WSL' "WSL/container disk '$($b.Distro)' is $($b.Size) on the system drive. VHDX files only grow; see references/cleanup.md for compacting or moving it."
}
$wslCfgPath = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path -LiteralPath $wslCfgPath) {
    $wc = Get-Content -LiteralPath $wslCfgPath -ErrorAction SilentlyContinue
    $mem = @($wc | Where-Object { $_ -match '^\s*memory\s*=' }) | Select-Object -First 1
    $cpu = @($wc | Where-Object { $_ -match '^\s*processors\s*=' }) | Select-Object -First 1
    $result.WslConfig = "present; " + $(if ($mem) { $mem.Trim() } else { 'memory not capped' }) + '; ' + $(if ($cpu) { $cpu.Trim() } else { 'processors not capped' })
} else {
    $result.WslConfig = 'no .wslconfig (WSL defaults: up to half the RAM, all cores)'
}
if ($wsl.Count -gt 0 -and -not ($result.WslConfig -match 'memory\s*=')) {
    Add-Finding 'info' 'WSL' 'WSL/containers are installed and WSL memory is not capped. If Windows builds slow down while containers run, see references/wsl-containers.md.'
}

# ---------------------------------------------------------------- git, Gradle, PostgreSQL

$tools = [ordered]@{}
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gv = Get-CmdOutput 'git' @('--version')
    $tools.Git = $gv
    foreach ($k in @('core.fsmonitor', 'core.untrackedCache', 'feature.manyFiles')) {
        $val = Get-CmdOutput 'git' @('config', '--global', '--get', $k)
        $tools["git --global $k"] = if ($val) { $val } else { '(not set)' }
    }
}
$gradleProps = Join-Path ([Environment]::ExpandEnvironmentVariables([string]$loc.'GRADLE_USER_HOME (Android builds)')) 'gradle.properties'
if (Test-Path -LiteralPath $gradleProps) {
    $gp = Get-Content -LiteralPath $gradleProps -ErrorAction SilentlyContinue
    foreach ($k in @('org.gradle.caching', 'org.gradle.parallel', 'org.gradle.configuration-cache')) {
        $line = @($gp | Where-Object { $_ -match "^\s*$([regex]::Escape($k))\s*=" }) | Select-Object -First 1
        $tools["Gradle $k"] = if ($line) { ($line -split '=', 2)[1].Trim() } else { '(not set)' }
    }
} elseif (Test-Path -LiteralPath (Split-Path $gradleProps -Parent)) {
    $tools.'Gradle user gradle.properties' = 'none (projects may set their own)'
}
$pgSvc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'postgresql*' })
$tools.PostgreSQLServices = if ($pgSvc.Count) { @($pgSvc | ForEach-Object { "$($_.Name) ($($_.Status))" }) } else { 'none installed as a Windows service' }
$result.OtherTools = $tools

# ---------------------------------------------------------------- build output folders

if (-not $DevRoot -or $DevRoot.Count -eq 0) {
    $DevRoot = @()
    foreach ($rv in $refsVols) { $DevRoot += "$($rv.Drive):\" }
    foreach ($c in @('source\repos', 'code', 'Code', 'dev', 'src', 'projects', 'Projects', 'git', 'repos')) {
        $p = Join-Path $env:USERPROFILE $c
        if ((Test-Path -LiteralPath $p) -and ($DevRoot -notcontains $p)) { $DevRoot += $p }
    }
}
$DevRoot = @($DevRoot | Select-Object -Unique)
$result.ScannedRoots = $DevRoot

$skipNames = @('.git', '.hg', '.svn', '$RECYCLE.BIN', 'System Volume Information', '.vs', '.idea', 'vendor')
$found = New-Object System.Collections.ArrayList

function Test-BuildDir([IO.DirectoryInfo]$d) {
    switch ($d.Name) {
        'target' {
            return (Test-Path -LiteralPath (Join-Path $d.FullName 'CACHEDIR.TAG')) -or
                   (Test-Path -LiteralPath (Join-Path $d.FullName 'debug')) -or
                   (Test-Path -LiteralPath (Join-Path $d.FullName 'release'))
        }
        'build' {
            $par = $d.Parent.FullName
            foreach ($m in @('pubspec.yaml', 'build.gradle', 'build.gradle.kts', 'CMakeLists.txt', 'package.json', 'settings.gradle')) {
                if (Test-Path -LiteralPath (Join-Path $par $m)) { return $true }
            }
            return $false
        }
        '.dart_tool' { return $true }
        'node_modules' { return $true }
    }
    return $false
}

function Find-BuildDirs([string]$dir, [int]$depth) {
    if ($depth -gt $MaxDepth) { return }
    $children = $null
    try { $children = ([IO.DirectoryInfo]$dir).GetDirectories() } catch { return }
    foreach ($c in $children) {
        if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($skipNames -contains $c.Name) { continue }
        if (Test-BuildDir $c) {
            [void]$found.Add($c.FullName)
            continue   # don't descend into build output
        }
        Find-BuildDirs $c.FullName ($depth + 1)
    }
}

foreach ($r in $DevRoot) {
    if (Test-Path -LiteralPath $r) { Find-BuildDirs $r 0 }
}
$buildRows = @()
foreach ($f in $found) {
    $bytes = Get-DirSize $f
    $buildRows += [pscustomobject]@{ Kind = Split-Path $f -Leaf; Path = $f; Bytes = $bytes; Size = Format-Size $bytes }
}
$buildRows = @($buildRows | Sort-Object Bytes -Descending)
$totalBuild = ($buildRows | Where-Object { $_.Bytes -gt 0 } | Measure-Object Bytes -Sum).Sum
$result.BuildOutput = [ordered]@{
    Count   = $buildRows.Count
    Total   = if ($SkipSizes) { 'skipped (-SkipSizes)' } else { Format-Size ([double]$totalBuild) }
    Largest = @($buildRows | Select-Object -First 25 Kind, Size, Path)
}
if (-not $SkipSizes -and $totalBuild -gt 50GB) {
    Add-Finding 'suggest' 'Disk' "Build-output folders total $(Format-Size ([double]$totalBuild)) across $($buildRows.Count) folders. Cleaning stale ones is free and safe; see references/cleanup.md."
}

# ---------------------------------------------------------------- admin-only notes

if (-not $IsAdmin) {
    Add-Finding 'info' 'Audit' "Not run as admin: Defender exclusions and per-volume Dev Drive details show '$NeedsAdmin'. Everything else is complete."
}
$result.Findings = $script:Findings

# ---------------------------------------------------------------- output

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    return
}

function Write-Section([string]$t) { Write-Output ''; Write-Output "== $t ==" }

Write-Output 'Dev PC audit (read-only; nothing was changed)'
Write-Output "Generated: $($result.GeneratedAt)   Admin: $IsAdmin"

Write-Section 'System'
$result.System.GetEnumerator() | ForEach-Object { Write-Output ("  {0,-10} {1}" -f $_.Key, $_.Value) }

Write-Section 'Volumes and Dev Drive'
Write-Output ("  fsutil devdrv query: " + ($devDriveGlobal -replace '\s*\r?\n\s*', ' '))
$script:Volumes | Select-Object Drive, Label, FileSystem, Size, Free, FreePct, DevDrive | Format-Table -AutoSize | Out-String -Width 220 | Write-Output

Write-Section 'Microsoft Defender'
$def.GetEnumerator() | ForEach-Object {
    $v = $_.Value
    if ($v -is [array]) { $v = if ($v.Count) { ($v -join '; ') } else { '(none)' } }
    Write-Output ("  {0,-22} {1}" -f $_.Key, $v)
}

Write-Section 'Toolchains, caches and temp'
$toolRows | Format-Table What, Drive, Size, Path -AutoSize | Out-String -Width 220 | Write-Output
Write-Output "  sccache: $($result.Sccache)"
if ($result.CargoGlobalConfig) {
    $cg = $result.CargoGlobalConfig
    Write-Output "  cargo global config $($cg.Path): linker set=$($cg.SetsLinker), [env] set=$($cg.SetsEnv), rustc-wrapper set=$($cg.SetsWrapper)"
}

Write-Section 'Windows Search'
Write-Output "  Service: $($search.Service)"
if ($search.IndexedFolders -is [array]) { Write-Output ("  Indexed folders: " + ($search.IndexedFolders -join '; ')) } else { Write-Output "  Indexed folders: $($search.IndexedFolders)" }
$perDrive | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

Write-Section 'Power'
Write-Output "  $($result.PowerPlan)"

Write-Section 'Other security features (report only; decisions are the user''s)'
$sec.GetEnumerator() | ForEach-Object { Write-Output ("  {0,-28} {1}" -f $_.Key, $_.Value) }

Write-Section 'WSL and container disks'
if ($wsl.Count) { $wsl | Format-Table Distro, Drive, Size, Disk -AutoSize | Out-String -Width 220 | Write-Output } else { Write-Output '  none found' }
Write-Output "  .wslconfig: $($result.WslConfig)"

Write-Section 'Git, Gradle, PostgreSQL'
$tools.GetEnumerator() | ForEach-Object {
    $v = $_.Value
    if ($v -is [array]) { $v = $v -join '; ' }
    Write-Output ("  {0,-36} {1}" -f $_.Key, $v)
}

Write-Section "Build output (roots: $($DevRoot -join ', '); depth $MaxDepth)"
Write-Output "  $($buildRows.Count) folders, total $($result.BuildOutput.Total)"
if ($buildRows.Count) { $result.BuildOutput.Largest | Format-Table -AutoSize | Out-String -Width 220 | Write-Output }

Write-Section 'Findings'
if ($script:Findings.Count -eq 0) { Write-Output '  nothing stands out' }
foreach ($f in $script:Findings) { Write-Output ("  [{0}] {1}: {2}" -f $f.Level, $f.Area, $f.Text) }
Write-Output ''
Write-Output 'Next: measure before changing anything (see the skill''s references). This script changed nothing.'
