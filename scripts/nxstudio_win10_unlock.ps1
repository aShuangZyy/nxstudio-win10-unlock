<#
    nxstudio_win10_unlock.ps1   (v3)
    ------------------------------------------------------------------
    让 Nikon NX Studio 1.10.x 的官方安装包在 Windows 10 上继续安装。

    NX Studio 1.10 的 Win10 封锁是【三处纯数据开关】，全部在运行时/系统里可改写：

    门槛 1  %TEMP%\{GUID}\{GUID}\WinVer.ini            (ASCII, 安装包自带)
            [WinOSVersion]
            10.0 = 10.0.21999        <- 要求内部版本 >= 21999（= Win11）

    门槛 2  %TEMP%\{GUID}\{GUID}\welcome\Items\Launch.ini   (UTF-16LE, 带 BOM)
            [TargetOS\64bit]
            Win11.0_Over="Welcome11_64"   <- 没有 Win10.0_Over
            Welcome.exe 用内部字符串 "Win%d.%d" + "_Over" 拼出 Win10.0_Over 查不到就判不支持

    门槛 3  C:\Program Files\Common Files\Nikon\WinVer.ini   (全局副本，本机已存在)
            内容同样是 10.0 = 10.0.21999；Welcome.exe 里硬编码了这个路径
            （字符串 "C:\Program Files\Common Files\Nikon\WinVer.ini" 与 "C:\WinVer.ini"），
            这是前两次跑仍然弹“您的操作系统上未运行 尼康工坊。”的真正原因。

    本脚本：提权 → 备份并放宽全局 WinVer.ini → 起后台线程持续改写临时目录里的两个文件
    与全局文件 → 启动安装包 →（可选）记录界面文字并自动点“安装”。

    注意：会修改 Common Files\Nikon\WinVer.ini（先自动备份成 *.bak_nxstudio_win10）。
          不要修改原始 exe（内容被压缩，且会破坏尼康数字签名）。

    用法：
      powershell -ExecutionPolicy Bypass -File .\nxstudio_win10_unlock.ps1 -Click
      powershell -ExecutionPolicy Bypass -File .\nxstudio_win10_unlock.ps1 -DryRun
      powershell -ExecutionPolicy Bypass -File .\nxstudio_win10_unlock.ps1 -Stage -KeepStaged
      powershell -ExecutionPolicy Bypass -File .\nxstudio_win10_unlock.ps1 -RestoreWinVer
#>
[CmdletBinding()]
param(
    [string]$Installer,
    [string]$MinVersion = '10.0.19041',
    [switch]$Stage,
    [switch]$KeepStaged,
    [switch]$StubWelcome,
    [switch]$Click,
    [switch]$DryRun,
    [switch]$RestoreWinVer,     # 只把全局 WinVer.ini 从备份恢复回去
    [int]$TimeoutMinutes = 40
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$logFile   = Join-Path $scriptDir 'nxstudio_win10_unlock.log'
$realTemp  = $env:TEMP
$globalIni = 'C:\Program Files\Common Files\Nikon\WinVer.ini'
$rootIni   = 'C:\WinVer.ini'

function Log([string]$m) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $m
    Write-Host $line
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch {}
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
              [Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------- 恢复模式 ----------------
if ($RestoreWinVer) {
    if (-not $isAdmin) { Write-Host '恢复需要管理员权限，请用管理员 PowerShell 运行。'; exit 1 }
    foreach ($t in @($globalIni, $rootIni)) {
        $bak = "$t.bak_nxstudio_win10"
        if (Test-Path -LiteralPath $bak) {
            Copy-Item -LiteralPath $bak -Destination $t -Force
            Log "已恢复 $t （来自 $bak）"
        } else { Log "没有备份：$bak" }
    }
    exit 0
}

# ---------------- 自提权 ----------------
if (-not $isAdmin -and -not $DryRun) {
    Write-Host '需要管理员权限，正在重新以管理员身份启动（请在 UAC 对话框点“是”）...'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Installer)   { $a += @('-Installer', ('"{0}"' -f $Installer)) }
    if ($MinVersion)  { $a += @('-MinVersion', $MinVersion) }
    if ($Stage)       { $a += '-Stage' }
    if ($KeepStaged)  { $a += '-KeepStaged' }
    if ($StubWelcome) { $a += '-StubWelcome' }
    if ($Click)       { $a += '-Click' }
    try   { Start-Process powershell -Verb RunAs -ArgumentList $a | Out-Null; exit 0 }
    catch { Write-Host "提权失败：$($_.Exception.Message)"; exit 1 }
}

# ---------------- 定位安装包 ----------------
if (-not $Installer) {
    $Installer = (Get-ChildItem -Path $scriptDir -Filter 'S-NXSTDO-*.exe' -ErrorAction SilentlyContinue |
                  Select-Object -First 1).FullName
}
if (-not $Installer -or -not (Test-Path -LiteralPath $Installer)) {
    Write-Host '找不到安装包，请用 -Installer "完整路径\S-NXSTDO-....exe" 指定。'
    exit 1
}
Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
Log "会话开始 (管理员=$isAdmin, Click=$Click, StubWelcome=$StubWelcome)"
Log "安装包: $Installer"
Log "目标最小版本: $MinVersion"

$iniText = "[Info]`r`nFileVer = 1`r`n`r`n[WinOSVersion]`r`n10.0 = $MinVersion`r`n11.0 = `r`n"

# ---------------- 门槛 3：全局 WinVer.ini ----------------
$globalTargets = @($globalIni, $rootIni) | Where-Object { Test-Path -LiteralPath $_ }
if ($globalTargets.Count -eq 0) { Log '未发现全局 WinVer.ini（无需处理）' }
foreach ($t in $globalTargets) {
    $cur = Get-Content -LiteralPath $t -Raw -ErrorAction SilentlyContinue
    $bak = "$t.bak_nxstudio_win10"
    Log ("全局文件 $t 原内容: " + (($cur -replace "`r`n", ' | ').Trim()))
    if ($DryRun) {
        Log "DryRun：会把 $t 备份为 $bak，然后改成 10.0 = $MinVersion"
        continue
    }
    if (-not (Test-Path -LiteralPath $bak)) {
        try {
            Copy-Item -LiteralPath $t -Destination $bak -Force -ErrorAction Stop
            Log "已备份 $t -> $bak"
        } catch { Log "备份 $t 失败：$($_.Exception.Message)" }
    } else {
        Log "备份已存在：$bak"
    }
    if (-not $isAdmin) {
        Log "跳过（需要管理员）：$t"
    } else {
        try {
            Set-Content -LiteralPath $t -Value $iniText -Encoding ASCII -Force -ErrorAction Stop
            Log "已修正全局文件 $t"
        } catch { Log "改写 $t 失败：$($_.Exception.Message)" }
    }
}

# ---------------- 清理残留 ----------------
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match '^_is' -or $_.ProcessName -in @('Welcome', 'DisplayRTF') } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ---------------- 后台补丁线程 ----------------
$stub   = Join-Path $env:SystemRoot 'System32\hostname.exe'
$doStub = [bool]$StubWelcome

$job = Start-Job -ScriptBlock {
    param($iniText, $minVersion, $doStub, $stub, $logFile, $realTemp, $globalList)

    $bom = [byte[]](0xFF, 0xFE)

    function Patch-LaunchIni([string]$path, [string]$logFile) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $hasBom = ($bytes.Length -gt 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
            $text = if ($hasBom) { [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
                    else         { [System.Text.Encoding]::Unicode.GetString($bytes, 0, $bytes.Length) }
            if ($text -notmatch 'Win10\.0_Over') {
                $m = [regex]::Match($text, '(?m)^\[TargetOS\\64bit\][^\r\n]*\r?\n')
                if ($m.Success) {
                    $new = $text.Insert($m.Index + $m.Length, "Win10.0_Over=`"Welcome11_64`"`r`n")
                    $out = New-Object System.Collections.Generic.List[byte]
                    $out.AddRange($bom)
                    $out.AddRange([System.Text.Encoding]::Unicode.GetBytes($new))
                    [System.IO.File]::WriteAllBytes($path, $out.ToArray())
                    Add-Content -LiteralPath $logFile -Value ('{0}  已修正 {1}（加入 Win10.0_Over）' -f (Get-Date -Format 'HH:mm:ss.fff'), $path) -Encoding UTF8
                }
            }
        } catch { }
    }

    $deadline = (Get-Date).AddMinutes(60)
    $lastDeep = Get-Date
    while ((Get-Date) -lt $deadline) {
        # 全局文件（安装程序可能随时重写）
        foreach ($g in $globalList) {
            try {
                $cur = Get-Content -LiteralPath $g -Raw -ErrorAction Stop
                if ($cur -notmatch [regex]::Escape($minVersion)) {
                    Set-Content -LiteralPath $g -Value $iniText -Encoding ASCII -Force -ErrorAction Stop
                    Add-Content -LiteralPath $logFile -Value ('{0}  已修正全局 {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $g) -Encoding UTF8
                }
            } catch { }
        }
        # 门槛 1
        foreach ($f in (Get-ChildItem "$realTemp\*\*\WinVer.ini" -Force -ErrorAction SilentlyContinue)) {
            try {
                $cur = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
                if ($cur -notmatch [regex]::Escape($minVersion)) {
                    Set-Content -LiteralPath $f.FullName -Value $iniText -Encoding ASCII -Force -ErrorAction Stop
                    Add-Content -LiteralPath $logFile -Value ('{0}  已修正 {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $f.FullName) -Encoding UTF8
                }
            } catch { }
        }
        # 门槛 2
        foreach ($f in (Get-ChildItem "$realTemp\*\*\welcome\Items\Launch.ini" -Force -ErrorAction SilentlyContinue)) {
            Patch-LaunchIni $f.FullName $logFile
        }
        # 深层兜底
        if (((Get-Date) - $lastDeep).TotalMilliseconds -gt 500) {
            $lastDeep = Get-Date
            $roots = Get-ChildItem $realTemp -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^\{[0-9A-Fa-f-]{36}\}$' }
            foreach ($root in $roots) {
                foreach ($f in (Get-ChildItem $root.FullName -Recurse -Depth 5 -Filter 'WinVer.ini' -Force -ErrorAction SilentlyContinue)) {
                    try {
                        $cur = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
                        if ($cur -notmatch [regex]::Escape($minVersion)) {
                            Set-Content -LiteralPath $f.FullName -Value $iniText -Encoding ASCII -Force -ErrorAction Stop
                            Add-Content -LiteralPath $logFile -Value ('{0}  已修正 {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $f.FullName) -Encoding UTF8
                        }
                    } catch { }
                }
                foreach ($f in (Get-ChildItem $root.FullName -Recurse -Depth 5 -Filter 'Launch.ini' -Force -ErrorAction SilentlyContinue)) {
                    Patch-LaunchIni $f.FullName $logFile
                }
            }
        }
        if ($doStub) {
            foreach ($w in (Get-ChildItem "$realTemp\*\*\welcome\Welcome.exe" -Force -ErrorAction SilentlyContinue)) {
                try {
                    if ($w.Length -gt 100000) {
                        Copy-Item -LiteralPath $stub -Destination $w.FullName -Force -ErrorAction Stop
                        Add-Content -LiteralPath $logFile -Value ('{0}  已替换 {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $w.FullName) -Encoding UTF8
                    }
                } catch { }
            }
        }
        Start-Sleep -Milliseconds 25
    }
} -ArgumentList $iniText, $MinVersion, $doStub, $stub, $logFile, $realTemp, @($globalTargets)

# ---------------- 启动 ----------------
$setupArgs = @('/debuglog')
if ($Stage) { $setupArgs += '/stage_only' }

if ($DryRun) {
    Log 'DryRun：不启动安装包。'
    Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
    exit 0
}

Log ('启动: ' + $Installer + ' ' + ($setupArgs -join ' '))
$proc = Start-Process -FilePath $Installer -ArgumentList $setupArgs -WorkingDirectory $scriptDir -PassThru
Log "安装进程 PID=$($proc.Id)；后台补丁线程已就绪"

# ---------------- UI 观察（可选点击） ----------------
$uiaOk = $false
try {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $uiaOk = $true
} catch { Log "UI 自动化不可用：$($_.Exception.Message)" }

$prefer   = @('安装', 'インストール', 'УСТАНОВИТЬ', 'Install', '下一步', '次へ', '&Next', 'はい', '开始')
$seenText = @{}
$clicked  = @{}
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
    if ($uiaOk) {
        $targets = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { ($_.ProcessName -eq 'Welcome' -or $_.ProcessName -match '^_is' -or $_.ProcessName -eq 'DisplayRTF') -and $_.MainWindowHandle -ne 0 }
        foreach ($t in $targets) {
            try {
                $ae = [System.Windows.Automation.AutomationElement]
                $cond = New-Object System.Windows.Automation.PropertyCondition($ae::ProcessIdProperty, $t.Id)
                $win = $ae::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
                if ($null -eq $win) { continue }
                $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($el in $all) {
                    $n = $el.Current.Name
                    if ($n -and $n.Trim().Length -gt 1 -and -not $seenText.ContainsKey($n)) {
                        $seenText[$n] = $true
                        Log "界面文字[$($t.ProcessName)]: $n"
                    }
                }
                if ($Click) {
                    $btnCond = New-Object System.Windows.Automation.PropertyCondition($ae::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
                    $btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
                    foreach ($k in $prefer) {
                        $hit = $null
                        foreach ($b in $btns) { if ($b.Current.Name -like "*$k*" -and $b.Current.IsEnabled) { $hit = $b; break } }
                        if ($hit) {
                            $key = "$($t.Id)|$($hit.Current.Name)"
                            if (-not $clicked.ContainsKey($key) -or ((Get-Date) - $clicked[$key]).TotalSeconds -gt 6) {
                                $clicked[$key] = Get-Date
                                $hit.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                                Log "已点击按钮 '$($hit.Current.Name)'"
                                Start-Sleep -Seconds 3
                            }
                            break
                        }
                    }
                }
            } catch { }
        }
    }
    Start-Sleep -Seconds 2
    $proc.Refresh()
}
if ($proc.HasExited) { Log "安装进程退出码 = $($proc.ExitCode)（0/3010 成功，1603 中止）" }
else                 { Log "等待超时（$TimeoutMinutes 分钟）" }

# ---------------- 收尾：再确认一次全局文件 ----------------
foreach ($t in $globalTargets) {
    try {
        $cur = Get-Content -LiteralPath $t -Raw -ErrorAction SilentlyContinue
        if ($cur -notmatch [regex]::Escape($MinVersion)) {
            Set-Content -LiteralPath $t -Value $iniText -Encoding ASCII -Force -ErrorAction Stop
            Log "收尾：重新修正全局文件 $t"
        }
    } catch { }
}

# ---------------- 可选：留存暂存目录 ----------------
if ($KeepStaged -or $Stage) {
    $dest = Join-Path $scriptDir 'stage_v3'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem $realTemp -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\{[0-9A-Fa-f-]{36}\}$' } |
        ForEach-Object {
            Log "复制暂存目录 $($_.FullName)"
            robocopy $_.FullName $dest /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
        }
    $s = Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    Log "已留存 $($s.Count) 个文件 / $([math]::Round($s.Sum/1MB,1)) MB"
}
Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -Force -ErrorAction SilentlyContinue
Log '结束。'
