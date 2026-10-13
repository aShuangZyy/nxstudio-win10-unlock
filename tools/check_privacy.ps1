<#
    check_privacy.ps1 —— 出包 / 上传前的隐私自检

    把整个发行目录里的文本文件扫一遍，查找"不该出现在公开产物里"的东西。

    两级规则：
      FAIL（退出码变 1，必须处理）
        本机用户目录路径、计算机名、邮箱地址（RFC 2606 保留的测试域名除外）、JWT 本体
      WARN（只提示，不影响退出码；人工看一眼）
        机器相关的 64 位十六进制密钥、UUID

    脚本自身不含任何个人信息 —— 全部规则都是通用正则，可以直接公开。

    用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_privacy.ps1
      powershell ... -File tools\check_privacy.ps1 -Path C:\some\other\folder
      powershell ... -File tools\check_privacy.ps1 -IncludeSessionModule   # 连登录快照一起查
      powershell ... -File tools\check_privacy.ps1 -AllowFile allow.txt    # 每行一条允许的正则

    退出码：0 = 没有 FAIL（可能有 WARN）；1 = 有 FAIL；2 = 路径不存在。
#>
param(
    [string]$Path = (Split-Path -Parent $PSScriptRoot),
    [switch]$IncludeSessionModule,
    [string]$AllowFile,
    [string[]]$SkipExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.exe', '.dll',
                                 '.zip', '.7z', '.pdb', '.pma', '.db', '.nkd', '.nki',
                                 '.icm', '.dat', '.pyc', '.pyo')
)

$ErrorActionPreference = 'Stop'

# ---- 必须处理：出现任何一条就不该发布 ----
$failRules = [ordered]@{
    'user folder path' = '(?i)C:\\+Users\\+(?!<)[^\\\s"''<>]+'
    'computer name'    = '(?i)\b(?:DESKTOP|LAPTOP|WIN)-[A-Z0-9]{6,}\b'
    'email address'    = '[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+'
    'raw JWT'          = 'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
}

# ---- 看一眼即可：多数是技术标识（安装包哈希、ProductCode），不自动判死 ----
$warnRules = [ordered]@{
    '64-hex key' = '(?i)\b[0-9a-f]{64}\b'
    'uuid'       = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
}

# RFC 2606 保留的测试域名，不算真邮箱
$benignEmail = '(?i)@(example\.(com|org|net)|.*\.invalid|.*\.test|localhost)$'

$allow = @()
if ($AllowFile -and (Test-Path -LiteralPath $AllowFile)) {
    $allow = @(Get-Content -LiteralPath $AllowFile | Where-Object { $_ -and $_ -notmatch '^\s*#' })
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host ("path not found: {0}" -f $Path) -ForegroundColor Red
    exit 2
}
$root = (Resolve-Path -LiteralPath $Path).Path
Write-Host ("== privacy check: {0} ==" -f $root) -ForegroundColor Cyan

function Test-Allowed([string]$value) {
    foreach ($a in $allow) { if ($value -match $a) { return $true } }
    return $false
}

$scanned = 0
$fails   = 0
$warns   = 0
foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    if ($f.FullName -like '*\.git\*') { continue }
    if (-not $IncludeSessionModule -and $f.Name -eq 'nxstudio_login_session.json') {
        Write-Host ("  skip  {0}  (it legitimately carries the session; add -IncludeSessionModule to check it)" -f $f.Name)
        continue
    }
    if ($SkipExtensions -contains $f.Extension.ToLower()) { continue }
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -eq 0) { continue }

    # 粗略的二进制判定：前 8 KB 出现 NUL 就当成二进制跳过
    $probe  = [Math]::Min(8192, $bytes.Length)
    $isText = $true
    for ($i = 0; $i -lt $probe; $i++) { if ($bytes[$i] -eq 0) { $isText = $false; break } }
    if (-not $isText) { continue }

    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $scanned++
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')

    foreach ($k in $failRules.Keys) {
        foreach ($m in [regex]::Matches($text, $failRules[$k])) {
            $v = $m.Value
            if ($k -eq 'email address' -and $v -match $benignEmail) { continue }
            if (Test-Allowed $v) { continue }
            $fails++
            $sample = if ($v.Length -gt 60) { $v.Substring(0, 60) + '...' } else { $v }
            Write-Host ("  FAIL  {0,-48} {1,-17} {2}" -f $rel, $k, $sample) -ForegroundColor Red
        }
    }
    foreach ($k in $warnRules.Keys) {
        foreach ($m in [regex]::Matches($text, $warnRules[$k])) {
            $v = $m.Value
            if (Test-Allowed $v) { continue }
            $warns++
            $sample = if ($v.Length -gt 60) { $v.Substring(0, 60) + '...' } else { $v }
            Write-Host ("  warn  {0,-48} {1,-17} {2}" -f $rel, $k, $sample) -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host ("{0} text file(s) scanned | FAIL={1}  warn={2}" -f $scanned, $fails, $warns)
if ($fails -eq 0) {
    Write-Host 'CLEAN - nothing personal; review the warn lines above by eye.' -ForegroundColor Green
    exit 0
}
Write-Host 'DIRTY - fix every FAIL above before publishing.' -ForegroundColor Red
exit 1
