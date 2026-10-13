# NOTICE / 免责与商标声明

## 本仓库不包含任何尼康（Nikon）二进制文件

仓库里只有：自己编写的 PowerShell 脚本、说明文档、以及**脱敏后的文本证据**（日志片段、字符串摘录）。
**没有**随附 Nikon NX Studio 安装包、DLL、EXE、RTF、图片或任何厂商二进制。
安装包请自行从尼康官方下载中心获取（见 README 中的链接）。

## 商标

- "Nikon"、"尼康"、"NX Studio"、"尼康工坊"、"Nikon Transfer 2" 等是尼康公司或其关联公司的商标或注册商标。
- "Windows" 是 Microsoft Corporation 的商标。
- "InstallShield" / "Flexera" 是 Flexera Software LLC 的商标。
本仓库与尼康公司、微软、Flexera 均无隶属或背书关系。

## 免责

本仓库提供的脚本会修改系统上的一个共享配置文件
（`C:\Program Files\Common Files\Nikon\WinVer.ini`，脚本会先自动备份为 `.bak_nxstudio_win10`），
并在安装过程中改写安装程序解包到临时目录的文件。

- 仅供**在你本人拥有/管理的设备**上，为恢复厂商已取消的兼容性而使用；
- 会使软件绕过厂商设定的系统要求，因此**不在厂商支持范围内**；
- 后续升级安装包（如 1.11/1.12）可能引入新的检查，需要重新分析；
- 使用前请自行确认所在地区的法律与许可协议，风险自负。

## 第三方内容

本仓库不复制任何厂商文档正文；报告中对 `setup.xml`、`WinVer.ini`、日志的引用均为
**为实现互操作性所必需的、极少量的事实性摘录**，并已注明来源。