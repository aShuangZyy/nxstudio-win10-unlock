# nxstudio-win10-unlock

让 **Nikon NX Studio 1.10.x**（尼康工坊）在 **Windows 10** 上安装并运行。

> 状态：**已实测通过** — NX Studio **1.10.1** 在 Windows 10 IoT Enterprise LTSC 2021 / 21H2 / **Build 19044.7725** 上
> 安装成功（安装程序退出码 0），并成功启动、载入 NEF 文件。

---

## 为什么装不上

尼康从 NX Studio **1.10.0** 起不再支持 Windows 10（官方下载页变更列表原文：“• 不再支持Windows 10。”）。
安装包把这个决定实现成了**三处纯数据开关**，没有任何真正的技术依赖：

| # | 位置 | 内容 | 拦截方式 |
|---|---|---|---|
| 1 | `%TEMP%\{GUID}\{GUID}\WinVer.ini`（安装包内置资源，ASCII） | `[WinOSVersion] 10.0 = 10.0.21999` | 要求内核 10.0 且内部版本 ≥ 21999（Win11）；不满足则 `Welcome.exe` 弹框并返回 5，套件按 `AbortCOde="5"` 中止（退出码 1603） |
| 2 | `%TEMP%\{GUID}\{GUID}\welcome\Items\Launch.ini`（**UTF-16LE**） | `[TargetOS\64bit]` 只有 `Win11.0_Over="Welcome11_64"` | `Welcome.exe` 用内部字符串 `Win%d.%d` + `_Over` 拼出 `Win10.0_Over` 去查界面段落，查不到即判“不支持的操作系统” |
| 3 | `C:\Program Files\Common Files\Nikon\WinVer.ini`（**机器级全局副本**） | `10.0 = 10.0.21999` | `Welcome.exe` 内硬编码了该路径（还有 `C:\WinVer.ini`）；只改临时目录那份没用 |

三处都是"版本号字符串"，改成 `10.0 = 10.0.19041` 即可放行 Win10。

## 用法

需要 **管理员权限**（全局文件在 `Program Files` 下；且 InstallShield 给自己的暂存目录设了
`Users: 只读 / Administrators: 完全控制` 的 ACL，普通权限写入会被拒绝）。

```powershell
# 在放着 S-NXSTDO-*.exe 的目录里执行；脚本会自提权（一次 UAC）
powershell -ExecutionPolicy Bypass -File .\scripts\nxstudio_win10_unlock.ps1 -Click
```

脚本流程：

1. 自提权；
2. 备份并放宽全局 `Common Files\Nikon\WinVer.ini`（备份为 `.bak_nxstudio_win10`）；
3. 后台线程 25 ms 轮询，持续改写三处开关（含内层安装包的 `WinVer.ini`）；
4. 启动官方安装包；`-Click` 会用 UI 自动化把界面文字写进日志并自动点“安装”；
5. 全程记录到 `nxstudio_win10_unlock.log`；退出后再确认一次全局文件。

| 参数 | 作用 |
|---|---|
| `-Click` | 自动点击正向按钮（安装 / インストール / Install / 下一步…），并记录所有界面文字 |
| `-StubWelcome` | 兜底：把 `welcome\Welcome.exe` 换成返回 0 的桩程序 |
| `-Stage` | 以 `/stage_only` 运行，只解包不安装（用于把内层包抓到磁盘留档） |
| `-KeepStaged` | 结束后把暂存目录复制到 `.\stage_v3\` |
| `-MinVersion 10.0.10240` | 进一步压低门槛（默认 `10.0.19041`） |
| `-RestoreWinVer` | 把全局 `WinVer.ini` 从备份还原 |
| `-DryRun` | 只打印将要改什么，不启动安装包、不需要管理员 |

### 成功判据

日志里应出现这三行，随后是正常的欢迎界面：

```
已备份 C:\Program Files\Common Files\Nikon\WinVer.ini -> ....bak_nxstudio_win10
已修正全局文件 C:\Program Files\Common Files\Nikon\WinVer.ini
已修正 ...\{GUID}\welcome\Items\Launch.ini（加入 Win10.0_Over）
```

最终 `安装进程退出码 = 0`，日志出现 `尼康工坊已成功安装`。

## 实测结果

| 项目 | 结果 |
|---|---|
| 系统 | Windows 10 IoT Enterprise LTSC 2021 / 21H2 / 19044.7725 |
| 安装包 | `S-NXSTDO-011001WF-ALLIN-ALL___.exe`（NX Studio 1.10.1.30030，SHA256 `ED54F890…C25B`） |
| 安装结果 | `尼康工坊 1.10.1` → `C:\Program Files\Nikon\NXStudio\`，退出码 0 |
| 附带升级 | Nikon Transfer 2 2.20.1 → 2.21.0 |
| 运行 | `NXStudio.exe` 1.10.1.3003 正常启动并载入 NEF |

## 仓库内容

```
scripts/nxstudio_win10_unlock.ps1     主脚本（v3）
docs/NXStudio-Win10-可行性报告.md      完整分析：样本、三条证据链、可行/不可行方案、风险
docs/evidence/01..05                   脱敏证据：Welcome.exe 实测对照、套件日志关键行、
                                       成功安装日志、载荷流结构分析、安装后系统状态
tools/stream_analysis.py               载荷流分析（证明无法对 exe 做等长字节替换）
```

**本仓库不包含尼康的任何二进制**（安装包、DLL、EXE、RTF、图片一个都没有）。安装包请自行获取：
<https://downloadcenter.nikonimglib.com/zh-cn/download/sw/271.html>

> 编码提示：`scripts/*.ps1` 一律保存为 **UTF-8 with BOM**——Windows PowerShell 5.1 读无 BOM 的
> 中文脚本会按 ANSI 解码而报错；PowerShell 7 无此问题。

## 注意

- 唯一被改动的系统文件是 `C:\Program Files\Common Files\Nikon\WinVer.ini`，**有自动备份**，可用 `-RestoreWinVer` 还原；
  原始安装包 exe **一个字节都没动**，尼康的数字签名与哈希保持有效。
- 这是"绕过厂商系统要求"，不在尼康支持范围内；升级到新版本后门槛可能变化，需要重新分析。
- 详见 [NOTICE.md](NOTICE.md)（商标与免责声明），代码以 [MIT](LICENSE) 授权。