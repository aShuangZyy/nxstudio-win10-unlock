# CHANGELOG

## v3 — 2026-10-13
- 定位到第三道门槛：机器级全局 `C:\Program Files\Common Files\Nikon\WinVer.ini`（`Welcome.exe` 内硬编码路径）。
- 新增：自动备份并放宽该全局文件、运行期持续监控、退出后再确认；新增 `-RestoreWinVer` 还原。
- **实测通过**：NX Studio 1.10.1 在 Windows 10 IoT Enterprise LTSC 2021（19044.7725）上安装成功（退出码 0），
  并成功启动、载入 NEF。

## v2 — 2026-10-13
- 定位到第二道门槛：`welcome\Items\Launch.ini` 的 `[TargetOS\64bit]` 只有 `Win11.0_Over`。
- 新增 UTF-16LE 字节级插入 `Win10.0_Over="Welcome11_64"`；新增 `-Click`（UI 自动化记录界面文字并点“安装”）。

## v1 — 2026-10-13
- 定位第一道门槛 `WinVer.ini`（`10.0 = 10.0.21999`）并实现运行期改写（需管理员：暂存目录 ACL 仅 Administrators 可写）。