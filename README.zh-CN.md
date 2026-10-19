# WorkBuddy AI 国际版 Linux 移植

[简体中文](README.zh-CN.md) · [English](README.md)

本项目为 **WorkBuddy AI 国际版（`workbuddy.ai`）** 提供一套可复用的 Linux 构建流程：在你自己的电脑上使用从官方渠道取得的 macOS DMG，转换为 Linux 应用并打包为 Debian `.deb`。

当前已验证的候选版本为 **5.8.4.41366630**，目标架构为 **x86_64/amd64**，DMG 内 Electron 版本为 **37.10.3**。用户已在 Kali Linux 桌面确认应用可启动、沿用现有会话并正常进行 AI 对话。新版独立 Google OAuth 登录与回跳、本地文件访问、内置终端和通知等仍需人工验证；完整记录见 [`BUILD_REPORT.md`](BUILD_REPORT.md)。

> **非官方项目。** 本项目与腾讯无关联，也未获得腾讯认可或支持。WorkBuddy AI 应用及其商标归腾讯所有。开始前请阅读 [`DISCLAIMER.md`](DISCLAIMER.md)。

## 项目做什么

WorkBuddy AI 国际版没有官方 Linux 客户端。本仓库提供构建脚本、补丁和文档，调用两个已有的开源移植工具链，将用户本地的官方 DMG 转换成 Linux 应用树，并生成 `.deb`。DMG、应用资源和生成的包不应提交到 Git 仓库；构建过程在本机完成。

```text
官方 WorkBuddy 国际版 macOS DMG（由用户取得）
                 │
                 ▼
LX2000WASD/workbuddy-international-linux
DMG 转 Linux 应用树；本仓库固定上游提交并应用兼容性补丁
                 │
                 ▼
Xboxpig/workbuddy-desktop-linux
Linux 应用树打包为 DEB；本仓库应用桌面和依赖补丁
                 │
                 ▼
workbuddy-ai-linux
版本化构建脚本、补丁、用户级安装工具和验证文档
```

本项目针对国际版 `workbuddy.ai`，不使用 `workbuddy.cn` 国内版安装包。现有 `build.sh` 保留旧版 5.5.2 稳定构建基线；`build-latest-candidate.sh` 是 5.8.4 的独立候选构建入口。

## 当前版本与验证情况

| 项目 | 状态 |
|---|---|
| WorkBuddy AI 版本 | 5.8.4.41366630，国际版 |
| DMG 架构 | Intel x86_64；不是 ARM64 |
| Electron Linux Runtime | 37.10.3 x64，Node 22.21.1，modules ABI 136 |
| DEB | `workbuddy-ai_5.8.4.41366630_amd64.deb`，包架构 `amd64` |
| 桌面启动与 AI 对话 | 用户在 Kali 的真实桌面确认成功，沿用了既有登录会话 |
| 新的 Google OAuth 流程 | 未独立验证；本轮未重新登录 |
| DEB 系统级安装 | 已构建并静态检查；本轮未通过 dpkg 安装 |

本版本原生模块需要 `GLIBC_2.42`。构建和运行目标为 Kali Rolling（本轮主机 glibc 2.43）；Ubuntu 22.04/24.04 的 glibc 版本不满足这一要求。请在目标机器上先确认 `ldd --version` 和依赖项。

## 移植中处理的兼容问题

- **登录凭据初始化：** 5.8.4 在启动时调用腾讯专属凭据 API。Linux 补丁使用 Electron `safeStorage`，由 Secret Service 提供加密存储，并在 Electron 就绪后初始化。无法解密时不会覆盖已有凭据材料。
- **双 URI Scheme：** 同时注册 `workbuddy-ai://` 和 `workbuddy://`。前者出现在 OAuth 回调配置中，后者用于应用内部页面跳转。桌面入口和 MIME 配置都会声明两个 Scheme；维护脚本不擅自设为系统默认项。
- **Electron 沙盒：** 启动器不永久关闭 Chromium 沙盒；本轮 Kali 环境的 user namespace 检查通过。
- **原生模块与 ASAR：** 修复新版 ASAR 分组匹配限制，清理不能加载的空原生占位和外平台可执行文件，并对 SQLite、Koffi、PTY 等模块做了冒烟检查。
- **DEB 桌面集成：** 补充运行库依赖、托盘库、Secret Service、桌面数据库刷新和真实 `WM_CLASS` 设置。

源码中仍有部分跨平台资源和 `.cn` 字符串；未发现本轮使用国内版 DMG，但所有区域分支和 macOS 专属功能并未逐一验证。TLS 校验没有关闭。

## 环境要求

- Kali Rolling x86_64/amd64，glibc 2.42 或更高
- 约 4 GB 可用磁盘空间；实际空间需求取决于临时目录和构建缓存位置
- `curl`、`git`、`patch`、`file`、`openssl`、`tar`、`rsync`、`dpkg-deb`、`fakeroot`
- Node.js 20+、npm 和 Python 3
- DEB 声明的 Electron 运行库；系统安装时由 apt 处理依赖

不要把 Linux 构建目录放在 NTFS 分区。构建需要正确的符号链接、权限和可执行文件语义。构建输出和日志保留在被 Git 忽略的 `artifacts/` 与 `logs/` 目录。

## 快速构建

```bash
git clone https://github.com/JackWesleyy/workbuddy-ai-linux.git
cd workbuddy-ai-linux

# 获取固定提交的上游工具链并应用本仓库补丁
./bootstrap.sh

# 使用官方国际版 x64 DMG 构建 5.8.4 候选版及 DEB
./build-latest-candidate.sh
```

DMG 路径、Electron 版本、运行时路径和校验值都可以配置。建议先读脚本帮助与完整流程：

```bash
./build-latest-candidate.sh --help
./tools/workbuddy_intl_release_probe.py --channel mac-x64
./tools/workbuddy_prepare_new_port.py --help
```

只构建 Linux 应用树，或只对现有应用树打包：

```bash
./build-latest-candidate.sh --app-only
./build-latest-candidate.sh --deb-only
```

版本升级、DMG 检查、Electron 版本确认、SHA256 固定和失败日志保留流程见 [`docs/PORTING-WORKFLOW.md`](docs/PORTING-WORKFLOW.md)。本轮构建与验证明细见 [`BUILD_REPORT.md`](BUILD_REPORT.md)。

## 安装

推荐先使用用户级安装脚本，不需要 sudo：

```bash
APP_SOURCE="$PWD/artifacts/build/5.8.4.41366630-73952edb/app" \
  ./install-user.sh
workbuddy-ai
```

用户级安装写入 `~/.local`，并使用与国内版客户端分开的 `~/.workbuddy-ai/` 用户数据目录。卸载程序不会自动删除用户数据。

如果要系统级安装已生成的 `.deb`：

```bash
sudo dpkg -i artifacts/packages/workbuddy-ai_5.8.4.41366630_amd64.deb
sudo apt-get -f install
```

系统级安装会写入 `/opt` 和 `/usr`，需要 root 权限。它不会替换 `~/.local` 中的用户级安装。安装包没有在本轮通过 dpkg 安装验证。

## 桌面与登录回调

桌面入口同时注册 `workbuddy-ai://` 和 `workbuddy://`。安装后可以检查默认处理程序：

```bash
xdg-mime query default x-scheme-handler/workbuddy-ai
xdg-mime query default x-scheme-handler/workbuddy
```

安装脚本会刷新 MIME 数据库，但不会替你修改默认 URI Handler。若浏览器完成授权后应用没有响应，请查看 [`docs/uri-scheme-bug.md`](docs/uri-scheme-bug.md)。

标准国际版登录代码会将授权页交给桌面默认浏览器；当前候选版的全新 Google OAuth 与回跳尚未验证。登录页面若表现异常，先不要输入密码或验证码，检查浏览器默认程序和 Scheme 关联。

## 验证和故障排查

在真实桌面会话中启动并记录检查结果：

```bash
./verify-real-desktop.sh
./verify-real-desktop.sh --kill
```

提交前可运行仓库卫生检查：

```bash
./scripts/check-no-proprietary.sh
```

| 现象 | 可检查的原因 |
|---|---|
| 浏览器授权后应用没有登录 | URI Scheme 未关联；检查 `x-scheme-handler/workbuddy-ai` 与 `x-scheme-handler/workbuddy` |
| `bad option: --no-sandbox` | 环境中设置了 `ELECTRON_RUN_AS_NODE=1`；先运行 `unset ELECTRON_RUN_AS_NODE` |
| 窗口空白或 renderer 崩溃 | 检查 `/dev/shm` 空间；启动器会传入 `--disable-dev-shm-usage` |
| 打包时报磁盘空间不足 | 检查 `/tmp` 是否为小型 tmpfs，可将 `TMPDIR` 指向有空间的本地文件系统 |
| 缺少 `fakeroot` | 安装构建依赖 `fakeroot` 和 `dpkg-dev` |
| Dock 图标显示异常 | 检查 DEB 桌面文件中的 `StartupWMClass` |

更多环境问题见 [`docs/env-traps.md`](docs/env-traps.md)。

## 致谢

特别感谢 **[No1Hoo](https://github.com/No1Hoo)** 创建并公开最初的 `workbuddy-ai-linux` 项目，为 WorkBuddy AI 国际版的 Linux 移植提供了重要起点。本仓库是在原项目基础上的延续和维护。

也感谢以下上游项目及维护者提供移植工具链：

- **[LX2000WASD/workbuddy-international-linux](https://github.com/LX2000WASD/workbuddy-international-linux)**：负责 macOS DMG 到 Linux 应用树的转换。原项目版权归其贡献者及 Zeongit J. 所有。
- **[Xboxpig/workbuddy-desktop-linux](https://github.com/Xboxpig/workbuddy-desktop-linux)**：提供 Linux 桌面打包框架。原项目版权归 ilysenko 所有。
- **Electron**：提供 Linux 运行时。

本仓库通过固定上游 Commit 并应用独立补丁来使用这些项目，没有把上游仓库复制进提交历史。完整授权文本见 [`LICENSE`](LICENSE)。

## 目录结构

```text
├── bootstrap.sh                 获取固定版本的上游工具并应用补丁
├── build.sh                     旧版 5.5.2 稳定构建入口
├── build-latest-candidate.sh    5.8.4 版本化候选构建入口
├── install-user.sh              安装到 ~/.local
├── verify-real-desktop.sh       真实桌面启动检查
├── patches/                     上游工具链的独立补丁
├── tools/                       发布探针和候选构建脚本生成器
├── BUILD_REPORT.md              本轮构建和验证记录
├── INSTALL.md                   安装说明
├── ROLLBACK.md                  回滚说明
├── docs/                        移植流程、登录回调和环境说明
└── upstream/                    bootstrap 获取；不提交到 Git
```

## 许可与免责声明

本仓库自有代码使用 MIT 许可证，详见 [`LICENSE`](LICENSE)。WorkBuddy AI 应用为腾讯专有软件，本项目不属于腾讯官方客户端或支持渠道。使用者应自行确认其使用和分发方式符合腾讯条款及所在地法律。有关不分发官方 DMG、应用资源和构建产物的项目规则，请阅读 [`DISCLAIMER.md`](DISCLAIMER.md)。
