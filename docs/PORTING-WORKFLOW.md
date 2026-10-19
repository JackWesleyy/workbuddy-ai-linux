# WorkBuddy 国际版 Linux 移植工作流

本文记录如何从官方 `workbuddy.ai` Intel macOS DMG 生成 Linux x86_64 应用树和 `.deb`。整个转换都在本机完成；仓库只保存脚本、补丁和验证说明，不保存厂商应用文件。

## 1. 查询并锁定版本

只查询国际版 x64 更新 Feed：

```sh
./tools/workbuddy_intl_release_probe.py --channel mac-x64
```

记录 Feed 返回的产品版本、Build ID、DMG 下载地址和官方 SHA256。Linux Feed 的版本不能替代 macOS 国际版 DMG 的目标版本。保留已有 DMG 原件；若本机已有对应版本，直接复用本地文件。

## 2. 检查 DMG 和 Electron

确认文件名、签名信息、产品版本、Build ID 和架构。Intel 移植必须从 `darwin-x64` DMG 开始；`darwin-arm64` 不能作为 x64 产物使用。

使用可用的只读工具列出和提取 DMG（例如 `7z l` / `7z x`），检查 `.app/Contents/Info.plist`、Electron Framework 的 `Info.plist`、`app.asar`、`app.asar.unpacked`、`package.json`、`product.json` 及所有 `.node` 文件。产品版本和 Electron Framework 版本是两个不同值；后者用于挑选 Linux Runtime。记录原生模块 ABI、N-API 版本、Mach-O 文件以及 OAuth 和 URI Scheme 配置。

获取匹配版本的 Electron Linux x64 Runtime ZIP。优先从 Electron 官方 Release 的 `SHASUMS256.txt` 校验 SHA256；镜像可用于下载，但应将官方摘要固定在候选脚本中。只自行计算本地 SHA256 不能证明文件来源可信。

## 3. 生成独立候选脚本

`build.sh` 是稳定版入口，生成新版脚本时不要覆盖它。先阅读辅助工具选项：

```sh
./tools/workbuddy_prepare_new_port.py --help
```

示例：

```sh
python3 tools/workbuddy_prepare_new_port.py \
  --repo "$PWD" \
  --output build-5.8.5-candidate.sh \
  --dmg /path/to/WorkBuddy-darwin-x64-VERSION-BUILD.dmg \
  --dmg-sha256 OFFICIAL_FEED_SHA256 \
  --electron-version ELECTRON_VERSION \
  --electron-zip /path/to/electron-vELECTRON_VERSION-linux-x64.zip \
  --electron-sha256 OFFICIAL_ELECTRON_SHA256 \
  --koffi-version KOFFI_VERSION \
  --koffi-sha512 NPM_REGISTRY_SRI
```

输出文件存在时工具会拒绝覆盖。候选脚本把 DMG 默认放在版本隔离的 `artifacts/input/` 下，也接受 `DMG=/path/to/local.dmg`；校验值可通过 `DMG_SHA256`、`ELECTRON_ZIP_SHA256` 覆盖。审阅生成的差异，确认只有国际版配置和升级所需变更。

仓库内的 `build-latest-candidate.sh` 是 5.8.4.41366630 的已验证示例。后续版本应保留为单独的版本脚本或明确替换候选脚本，并同步更新 Build ID、官方 DMG 摘要、Electron 版本/摘要及 Koffi 来源摘要。

## 4. 获取上游并构建

```sh
./bootstrap.sh
./build-latest-candidate.sh --app-only
./build-latest-candidate.sh --deb-only
```

若 DMG 不在版本隔离的默认输入目录，传入其本地路径：

```sh
DMG=/path/to/local.dmg DMG_SHA256=OFFICIAL_FEED_SHA256 \
  ./build-latest-candidate.sh --app-only
```

`bootstrap.sh` 固定两套上游 Commit，并应用 `patches/` 中的补丁。已有同名 Git 工作树会先核对路径、Commit 和工作区状态；遇到脏工作区或非 Git 目录会停止并保留现场。不要用 `--force` 清理工作目录。

候选脚本按产品版本和 Build ID 隔离 Electron/npm 缓存、转换临时目录、包目录和日志。失败日志保留在 `logs/`；生成的应用树、DEB 和下载文件在 `artifacts/`。不需要把这些目录加入 Git。

## 5. 验证应用树和 DEB

构建完成后检查：

- Electron 是 Linux x86_64，版本与 DMG 中的 Electron Framework 相符。
- 所有 `.node` 原生模块都能加载，ABI 与当前 Electron 对应；检查 `better-sqlite3`、`node-pty`、Koffi 和其他原生扩展。
- 对应用内 ELF 执行 `file` 和 `ldd`，确认架构、GLIBC 要求和动态库依赖。
- 启动参数没有永久关闭 Chromium 沙盒；没有关闭 TLS 验证。
- `workbuddy-ai://` 与 `workbuddy://` 均有桌面入口登记，且安装脚本不擅自替换用户默认 Scheme Handler。
- 使用隔离用户目录和 Xvfb 做无凭据启动检查。不要在真实用户资料目录做破坏性测试，也不要读取或打印 Token、Cookie、API Key、会话数据库。
- 用 `dpkg-deb --info` 和 `dpkg-deb --contents` 检查版本、amd64 架构、依赖、桌面文件、图标、MIME 声明和可执行启动器。

记录测试边界：生成 `.deb` 只说明完成构建和静态打包检查。没有实际触发登录的版本应把 Google OAuth、回跳、AI 对话、文件访问、终端、托盘和通知明确留作人工验证。不要把未做的人工步骤描述成成功。

## 6. 用户级安装

安装前先正常退出 WorkBuddy，避免旧进程读取被替换的程序文件。普通用户可直接安装到 `~/.local`：

```sh
APP_SOURCE="$PWD/artifacts/build/VERSION-BUILD/app" ./install-user.sh
```

若要并行安装候选版本，可使用独立应用目录：

```sh
APP_SOURCE="$PWD/artifacts/build/VERSION-BUILD/app" \
APP_DIR_NAME="workbuddy-ai-VERSION" ./install-user.sh
```

脚本会刷新当前用户的启动器和桌面入口，但不会修改 `~/.workbuddy-ai/`，也不会更改默认 URI Handler。系统级 DEB 安装需要 root 权限；在授权前先检查所需依赖和安装命令。

## 7. 上传前仓库检查

```sh
./scripts/check-no-proprietary.sh
git diff --check
git status --short
```

只提交构建脚本、补丁和文档。禁止提交 DMG、Electron ZIP、`app.asar`、原生二进制、`.deb`、`artifacts/`、`logs/`、用户资料、凭据或任何会话内容。检查守卫会同时检查暂存文件和 Git 历史路径。

## 当前候选状态

当前构建目标为 WorkBuddy AI International 5.8.4.41366630 / Build ID `73952edb`，来自 macOS x64 DMG，Electron 37.10.3。用户在 Kali 桌面确认新版继续使用现有登录会话并可正常对话；没有重新发起 Google 登录，所以此版本的全新 OAuth 回跳仍未单独验证。详见 [`../BUILD_REPORT.md`](../BUILD_REPORT.md)。
