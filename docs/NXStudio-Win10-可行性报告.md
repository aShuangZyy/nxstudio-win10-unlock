# 尼康工坊 NX Studio 1.10.1 安装包"改成 Win10 可装"可行性研究报告

- 分析对象：`<REPO_DIR>\S-NXSTDO-011001WF-ALLIN-ALL___ (1).exe`
- 宿主系统：Windows 10 IoT Enterprise LTSC 2021 / 21H2 / **10.0.19044.7725**（AMD64，简体中文）
- 分析日期：2026-10-13
- 结论一句话：**可行，且已实测成功。** 拦人的不是技术依赖，而是尼康自己写死的三个版本号开关；把它们改掉后，NX Studio 1.10.1 在 Windows 10 21H2（19044）上安装成功并正常运行。

---

## 1. 样本信息

| 项目 | 值 |
|---|---|
| 文件名 | `S-NXSTDO-011001WF-ALLIN-ALL___ (1).exe` |
| 大小 | 262,628,168 字节（约 250.4 MB） |
| SHA256 | `ED54F89097D3277AC8966408FF1F1D20001CA3E21E3EDCC7EB18D707D4FCE25B` |
| 产品 | NX Studio 1.10.1.30030（尼康工坊） |
| 描述 | `Setup Launcher NX Studio` / InternalName = `SetupSuite` |
| 数字签名 | **有效**，CN=NIKON CORPORATION（DigiCert，2025-10-10 签发，含时间戳） |
| 封装类型 | InstallShield **Suite / Advanced UI** 引导器（SetupSuite 引擎）+ 内嵌 260 MB 压缩载荷 |
| 内层包 | `{327FA429-2B8C-4508-8538-037ECB4A9158}`（NX Studio，data1.cab/data2.cab/setup.exe）、`{83D48551-3FF2-437E-B931-BF45011C6F87}`（Nikon Transfer 2）、VC++ 2015-2022 Redist x86/x64、.NET 4.6.1(NDP461) |

宿主机实测：直接运行安装包 → 欢迎页后即中止，**退出码 1603**（InstallShield/MSI 的"致命错误"）。

---

## 2. 为什么 Win10 装不上：完整证据链

### 2.1 门槛就是一行 INI

安装包运行时会把内置资源解包到临时目录：

```
%TEMP%\{随机GUID}\{随机GUID}\
    ├─ setup.xml                 (InstallShield Suite 工程定义, 364 KB)
    ├─ WinVer.ini                (71 字节 —— 这就是门槛)
    ├─ Setup.inx / ISSetup.dll / ISRT.dll / Setup_UI.dll
    ├─ Launch_NXST_P.ini / BuildInfo.txt
    ├─ welcome\Welcome.exe       (尼康自己写的"欢迎/系统检查"界面)
    └─ rtf\ ... welcome\Items\ ...
```

`WinVer.ini` 原文（实测抓取）：

```ini
[Info]
FileVer = 1

[WinOSVersion]
10.0 = 10.0.21999
11.0 = 
```

含义：**对内核版本 10.0（Win10 与 Win11 都是 10.0）要求内部版本 ≥ 21999**。Win11 最低正式版是 22000；Win10 全系是 19041–19045。所以本机 10.0.19044 < 21999，直接判定"不支持"。

### 2.2 判决由尼康的 Welcome.exe 执行

`welcome\Welcome.exe`（915 KB，MFC，尼康签名）中包含这些符号：

```
ChkOS2
ChkOSVersionNumber() -> FALSE / TRUE
GetSectionStringFromOSVersion() ret:FALSE/TRUE getSection=%s
OS Info : Windows %d.%d
GetVersionExW
TargetOS / OSError / Nk_installerDef
```

它读取 `WinVer.ini` 的 `[WinOSVersion]` 段，用 `GetVersionExW` 取本机版本比较；不满足就弹框并返回错误码。

**实测（直接运行暂存出来的 Welcome.exe）**：

```
########## 控制组：原版 WinVer.ini (10.0.21999) ##########
WINDOW: '安装程序' class=#32770
  [Pane] 您的操作系统上未运行 尼康工坊。          <-- 这就是普通用户看到的那句提示
  [Pane] 确定
日志: OS Info : Windows 10.0 (10.0.19044)

########## 实验组：改成 10.0.19041 ##########
退出码 = 0，不再出现"操作系统不支持"提示
```

### 2.3 中止是怎么传导的

Suite 工程 `setup.xml` 里的动作定义：

```xml
<Actions>
  <CallExe Id="Welcome" DefaultCode="Ignore"
           File="[SETUPSUPPORTDIR]\welcome\Welcome.exe"
           Window="Show" WaitForExit="Yes" AbortCOde="5"/>
  <CallInstallScript Id="WelcomeStart" Arguments="WelcomeStart" ExecutionLevel="Invoker"/>
  ...
```

`Welcome.exe` 返回 5 → 该动作 Abort → 套件整体退出，退出码记录为 1603。套件日志（`/debuglog` 生成的 `InstallShield.log`）实测：

```
Engine: running with elevated privileges: yes
Resource was staged to '...\{ADCB3D57}\WinVer.ini'
Running event 'WelcomeStart'
Engine: property 'ExitFlg' value now 'true'
Running event 'ExitAction'
EXE for action 'ExitAction' returned value 0xfffffffe
Original exit status: 0x80070643, final exit status: 0x00000643   (= 1603)
```

### 2.4 第二道门槛（第一次实跑才暴露，同样在 ini 里）

2026-10-13 12:17 用 v1 脚本实跑（管理员，日志显示 `12:17:18.982 已修正 ...\WinVer.ini`，即门槛 1 已被改写），结果仍是 1603：

```
12:17:18  Resource was staged to '...\{809D1F00}\WinVer.ini'
12:17:20  Running event 'WelcomeStart'
12:17:52  Engine: property 'ExitFlg' value now 'true'      <- 32 秒后又判定中止
12:17:52  final exit status: 0x00000643                    (= 1603)
TEMP\Welcome_NXST_Installer.log:  Welcome Start ... Welcome Cancel
```

原因在 `%TEMP%\{GUID}\{GUID}\welcome\Items\Launch.ini`（**UTF-16LE**，带 BOM）：

```ini
[TargetOS]
[TargetOS\64bit]
Win11.0_Over="Welcome11_64"      ; ← 64 位只有 Win11 一项，没有 Win10
```

`Welcome.exe` 内实测存在宽字符串 `TargetOS`、`Win%d.%d`、`_Over`：它按当前系统版本拼出 `Win10.0_Over` 去查“用哪套欢迎界面”，查不到就等同于“不支持的操作系统”，用的还是同一个错误提示（`OSError=IDS_UI_SYSMSG_ERR_OS`，即“您的操作系统上未运行 尼康工坊。”）。

修复：在 `[TargetOS\64bit]` 下补一行 `Win10.0_Over="Welcome11_64"`（复用 Win11 的界面定义，里面只是 Install/Exit 两个按钮，没有版本相关逻辑）。字节级插入已验证：BOM 保留、日文注释未损坏、文件从 38062 B 变为 38120 B。

**结论：1.10 的 Win10 封锁是两处纯数据开关，两处都可改写。**

### 2.5 第三道门槛：全局 `WinVer.ini`（第二次实跑才暴露）

第二次实跑（12:25）两道门槛都改写成功，仍然弹同一个框：

```
12:25:40.834  已修正 ...\{49EBF7CD}\welcome\Items\Launch.ini（加入 Win10.0_Over）
12:25:41.460  已修正 ...\{49EBF7CD}\WinVer.ini
12:25:43.793  界面文字[Welcome]: 您的操作系统上未运行 尼康工坊。
12:25:47.821  安装进程退出码 = 1603
```

在 `Welcome.exe` 的字符串里发现两个**硬编码**路径：

```
C:\WinVer.ini
C:\Program Files\Common Files\Nikon\WinVer.ini
```

而本机 **`C:\Program Files\Common Files\Nikon\WinVer.ini` 真的存在**（71 字节，2024-05-27，由更早的尼康安装留下），内容与安装包内置的完全一样：

```ini
[Info]
FileVer = 1

[WinOSVersion]
10.0 = 10.0.21999
11.0 = 
```

即：门槛不只藏在安装包的临时目录里，还有一份**机器级全局副本**。只改临时目录那份没用——这就是前两次都失败的原因。

处理方式：改写该全局文件（先自动备份为 `WinVer.ini.bak_nxstudio_win10`），并在安装过程中持续监控（安装程序可能重新写入它）；脚本另带 `-RestoreWinVer` 可一键还原。

全盘搜索结果（确认没有第四份）：

```
71  C:\Program Files\Common Files\Nikon\WinVer.ini     ← 需要改
69  <REPO_DIR>\extract\{BEFDF4C9}\WinVer.ini     ← 抓出来的样本
```

### 2.6 尼康官方的说法（旁证）
- 尼康日本 FAQ（2026-01-15 更新）：NX Studio v1.10.x 对应 OS 只有 **Microsoft Windows 11（64bit）**。
- 尼康下载中心 1.10.0 页面 1.9.1→1.10.0 变更列表明确写着：**"• 不再支持Windows 10。"**
  同一版的功能变更是：新增 ZR 支持、胶片颗粒、除霾、R3D NE 支持、取消 Movie Editor、视频仅缩略图等——**没有任何一条在技术上必须 Win11**，属于"停止支持"性质的政策性门槛。

---

## 3. 改造可行性判定

| 方案 | 可行性 | 说明 |
|---|---|---|
| A. 直接十六进制改 exe 里的 `10.0.21999` | **不可行** | 实测：`10.0.21999`、`[Info]`、`WinOSVersion` 在整个 262 MB 文件里**一次都搜不到**。载荷是压缩存储的，只有文件名（`{327FA429-...}\data1.cab`、`WinVer.ini`、`Setup_UI.dll`… 共 258 个 UTF-16 文件名）是明文。要静态改就得先逆向 InstallShield 私有压缩流并原样重压，工作量/风险都不划算。 |
| B. 改写运行时临时文件 + 全局 `WinVer.ini` | **可行（三处门槛全部定位并改写成功）** | 见 §2.2、§2.4、§2.5。窗口期约 2–5 秒（资源解包 → WelcomeStart 之间），脚本 25 ms 轮询足够稳。**必须管理员权限**：既因为 `C:\Program Files\Common Files\Nikon\` 需要管理员，也因为 InstallShield 给暂存目录设了 `BUILTIN\Users: ReadAndExecute` + `BUILTIN\Administrators: FullControl` 的 ACL（普通权限写入直接 `Access to the path ... is denied`，已实测复现）。注意 `Launch.ini` 是 **UTF-16LE**，必须按宽字符改写。 |
| C. 顺带把 `welcome\Welcome.exe` 换成返回 0 的桩程序 | 可行（兜底） | `DefaultCode="Ignore"`，只要返回值不是 5 套件就继续。适合"欢迎界面需要点按钮、想全自动"的场景；代价是语言/区域走默认值。 |
| D. 用 `/stage_only` 把内层包抓到磁盘，之后脱离引导器直接装 | 逻辑上可行 | `/stage_only` 被引擎识别（日志：`Engine: command line specified stage only mode`），但**仍在欢迎门槛之后**才解包，所以必须先做 B。抓到 `{327FA429-...}\setup.exe`+`data1.cab`+`data2.cab` 后即可离线分发/离线安装。 |
| E. 伪装系统版本（改注册表 CurrentBuild 等） | 不推荐 | 会连带影响整个系统组件，风险远大于收益；且 `GetVersionExW` 可以从 PEB/manifest 取到真实版本，不可靠。 |
| F. 改直接用 1.9.1（官方支持 Win10 的最后一版） | **最省事、零风险** | 尼康官方已不提供旧版下载页，需从镜像站（filehorse 等）取 1.9.0/1.9.1。功能差异：没有 ZR/胶片颗粒/除霾/R3D NE。 |

**总判定：把 1.10.1 装上 Win10 是可行的，且改动只发生在运行时的临时文件上——原始 exe 一个字节都不用动，尼康的数字签名与哈希保持有效。**

---

## 4. 操作步骤

### 4.1 推荐：一键脚本（需在 UAC 弹窗点"是"，共一次）

```powershell
# 普通 PowerShell 里执行即可，脚本会自己提权；想全自动加 -Click
powershell -ExecutionPolicy Bypass -File <REPO_DIR>\nxstudio_win10_unlock.ps1 -Click
```

脚本做的事：

1. 自提权（一次 UAC）；
2. 备份并放宽机器级全局文件 `C:\Program Files\Common Files\Nikon\WinVer.ini`（备份为同名 `.bak_nxstudio_win10`）；
3. 后台起一个补丁线程，25 ms 轮询：
   - 全局 `WinVer.ini`（安装程序可能随时重写）；
   - `%TEMP%\*\*\WinVer.ini` → 写成 `10.0 = 10.0.19041`（门槛 1）；
   - `%TEMP%\*\*\welcome\Items\Launch.ini` → 在 `[TargetOS\64bit]` 下补 `Win10.0_Over="Welcome11_64"`（门槛 2，UTF-16LE 字节级插入）；
   - 每 500 ms 再深扫暂存目录（内层安装包如也有 WinVer.ini 一并处理）；
4. 启动官方安装包；`-Click` 时用 UI 自动化把界面文字记入日志并自动点“安装”类按钮；
5. 全过程写 `nxstudio_win10_unlock.log`；退出后再确认一次全局文件。

可选参数：

| 参数 | 作用 |
|---|---|
| `-Click` | 自动点击界面上的正向按钮（安装 / インストール / Install / 下一步…），并把所有界面文字写进日志 |
| `-StubWelcome` | 兜底：连欢迎界面一起跳过（把 `welcome\Welcome.exe` 换成返回 0 的桩） |
| `-Stage` | 以 `/stage_only` 运行，只解包不安装（用于把内层包抓到磁盘留档） |
| `-KeepStaged` | 结束后把 `%TEMP%` 下的暂存目录复制到 `.\stage_v3\` |
| `-MinVersion 10.0.10240` | 想更激进就把门槛压到 Win10 初版 |
| `-RestoreWinVer` | 把全局 `WinVer.ini` 从备份还原 |
| `-DryRun` | 只打印将要改的内容，不启动安装包、不需要管理员 |

### 4.2 手动版（等价，便于理解/排错）

```powershell
# 1) 管理员身份打开 PowerShell
# 1.5) 门槛 3：机器级全局副本（这一步最容易被忽略）
$g = 'C:\Program Files\Common Files\Nikon\WinVer.ini'
Copy-Item $g "$g.bak_nxstudio_win10" -Force
Set-Content $g "[Info]`r`nFileVer = 1`r`n`r`n[WinOSVersion]`r`n10.0 = 10.0.19041`r`n11.0 = `r`n" -Encoding ASCII -Force
# 2) 起后台补丁线程
$patch = "[Info]`r`nFileVer = 1`r`n`r`n[WinOSVersion]`r`n10.0 = 10.0.19041`r`n11.0 = `r`n"
Start-Job -ScriptBlock {
  param($p)
  while ($true) {
    Get-ChildItem "$env:TEMP\*\*\WinVer.ini" -Force -EA SilentlyContinue | ForEach-Object {
      try { if ((Get-Content $_.FullName -Raw) -notmatch '19041') {
              Set-Content $_.FullName $p -Encoding ASCII -Force } } catch {}
    }
    Start-Sleep -Milliseconds 25
  }
} -ArgumentList $patch

# 3) 运行安装包，按提示装完
& '<REPO_DIR>\S-NXSTDO-011001WF-ALLIN-ALL___ (1).exe'
```

门槛 2 的手工修法（同一线程里顺手做；注意是 UTF-16LE 文件）：

```powershell
$ini = "$env:TEMP\*\*\welcome\Items\Launch.ini"
Get-ChildItem $ini -Force -EA SilentlyContinue | ForEach-Object {
  $b = [IO.File]::ReadAllBytes($_.FullName)
  $t = [Text.Encoding]::Unicode.GetString($b, 2, $b.Length-2)
  if ($t -notmatch 'Win10\.0_Over') {
    $m = [regex]::Match($t, '(?m)^\[TargetOS\\64bit\][^\r\n]*\r?\n')
    if ($m.Success) {
      $new = $t.Insert($m.Index + $m.Length, "Win10.0_Over=`"Welcome11_64`"`r`n")
      $out = New-Object System.Collections.Generic.List[byte]
      $out.AddRange([byte[]](0xFF,0xFE)); $out.AddRange([Text.Encoding]::Unicode.GetBytes($new))
      [IO.File]::WriteAllBytes($_.FullName, $out.ToArray())
    }
  }
}
```

验证点（成功标志）：

- 不再出现"**您的操作系统上未运行 尼康工坊。**"；
- `%TEMP%\Welcome_NXST_Installer.log` 里出现 `Welcome Start` 之后是正常的欢迎/语言区域界面，而不是快速 `Welcome Cancel` + 1603；
- 安装程序退出码为 0（或 3010 = 需要重启）。

> 注意：请**交互式**运行，不要加 `/passive` 或 `/s`。实测 `/passive` 下尼康的欢迎界面无人点击，约 60 秒后会被当作"取消"（日志 `Welcome Cancel` / `ExitFlg=true`）而中止——这与系统门槛无关。要全自动就用 `-Click` 或 `-StubWelcome`。

### 4.4 实测结果（2026-10-13 完成）

第三次实跑（v3，三道门槛全部改写）后的日志：

```
12:28:24.887  已修正全局 C:\Program Files\Common Files\Nikon\WinVer.ini
12:28:24.887  已修正 ...\{3536D6BE}\welcome\Items\Launch.ini（加入 Win10_Over）
12:28:25.507  已修正 ...\{3536D6BE}\WinVer.ini
12:28:35.991  界面文字[_isC5D5]: 配置中
12:28:40.048  界面文字[_isC5D5]: 正在安装软件包 尼康工坊
12:29:02.354  界面文字[_isC5D5]: 正在安装软件包 Nikon Transfer 2
12:29:08.419  界面文字[_isC5D5]: 正在安装软件包 Profile
12:29:20.562  界面文字[_isC5D5]: 正在安装软件包 Optional Picture Control
12:29:36.763  界面文字[_isC5D5]: 尼康工坊已成功安装。单击“完成”退出向导。
12:29:46.861  安装进程退出码 = 0
```

安装后系统状态：

| 项目 | 结果 |
|---|---|
| 卸载列表 | `尼康工坊 1.10.1 → C:\Program Files\Nikon\NXStudio\` |
| 附带升级 | `Nikon Transfer 2` 2.20.1 → 2.21.0 |
| 主程序 | `NXStudio.exe` 1.10.1.3003（9.09 MB）、`SaveProcess.exe`、`NkLDTr.exe` |
| 启动实测 | 进程 `NXStudio` 正常驻留、主窗口标题 `尼康工坊`，并成功载入 NEF（工作集约 3.5 GB） |
| 全局文件 | `WinVer.ini` 已放宽为 `10.0 = 10.0.19041`，原文件备份在 `WinVer.ini.bak_nxstudio_win10` |

即：**门槛绕过后，应用本体在 Win10 上没有任何可见问题**（启动、载入 NEF 都正常）。

### 4.5 备选：装 1.9.1
如果只求"能用"，最稳的是 1.9.x（官方支持 Win10、无门槛）。缺点：拿不到尼康官方旧版下载，需要镜像站，且缺少 1.10 的新功能。

---

## 5. 风险与限制（必须知道）

1. ~~应用本体在 Win10 上是否 100% 正常，本次未能验证。~~ **已实测通过**：安装完成（退出码 0）、启动正常、能载入 NEF。仍建议自己再验证导出 JPEG、除霾、视频缩略图等重功能；极端场景（HEVC 硬解、HDR 显示器）可能与驱动相关。
2. **不要改原始 exe。** 一改签名立刻失效（现在是"Signature verified"），且压缩载荷无法等长替换。本方案全程只动运行时临时文件，签名不受影响。
3. **升级会被覆盖。** 以后尼康再发 1.11/1.12，同样门槛会回来，需重复一次本流程。
4. **需要一次管理员提权**：暂存目录 ACL 只允许 Administrators 写（实测普通权限写入被拒）。
5. **不属于尼康支持范围**：出问题尼康不负责；企业环境请先确认内部合规要求。

---

## 6. 交付物与证据文件

| 文件 | 内容 |
|---|---|
| `NXStudio_Win10_改造可行性报告.md` | 本报告 |
| `nxstudio_win10_unlock.ps1` | **v3**：一键提权 + 备份/改写机器级 `Common Files\Nikon\WinVer.ini`（门槛 3）+ 后台同时改 `WinVer.ini`（门槛 1）与 `welcome\Items\Launch.ini`（门槛 2，UTF-16LE）+ 可选 UI 自动点击与界面文字记录 + `-RestoreWinVer` 还原 |
| `extract\{BEFDF4C9}\` | 从 %TEMP% 抓出的 Suite 支持文件（`WinVer.ini`、`setup.xml`、`Welcome.exe`、`Setup.inx`、语言 DLL、Readme RTF 等 182 个文件） |
| `InstallShield.log` | Suite 引擎 `/debuglog` 全量日志（含 1603 的完整因果链） |
| `welcome_experiment.txt` | Welcome.exe 对照组/实验组实测结果（"您的操作系统上未运行 尼康工坊。"） |
| `watcher.log` / `elev_watcher.log` | 运行中打补丁的实测记录 |
| `patch_and_stage.ps1` / `elevate_ui_run.ps1` / `elevate_full_run.ps1` | 分析阶段用的实验脚本（补丁+点击+解包留档） |
| `stream_analysis.py` / `stream_analysis_out.txt` | 载荷流结构分析（明文字名目录 + 压缩数据，证明无法直接字节改） |
| `deepscan.py`、`binstrings.py`、`switches.py`、`strscan.py` | PE 结构 / 关键字 / 命令行开关 / 系统判断符号的取证脚本 |

## 7. 引用

- [尼康官方 FAQ：NX Studio 运行环境（Windows）—— 对应 OS 仅 Windows 11](https://nij.nikon.com/support/faq/products/article?articleNo=000060850)
- [尼康下载中心：尼康工坊 1.10.0（变更列表含"不再支持Windows 10"）](https://downloadcenter.nikonimglib.com/zh-cn/download/sw/271.html)
- [DPReview 论坛：NX Studio 1.10.0 and Windows 10](https://www.dpreview.com/forums/threads/nx-studio-1-10-0-and-windows-10.4820394/)
- [Cameraderie：Nikon - NX Studio v1.10 error on Windows 10](https://cameraderie.org/threads/nx-studio-v-1-10-error-on-windows-10.60102/)
