# WorkBuddy AI International 5.8.4 Linux 移植报告

## 结论

目标 DMG 是 WorkBuddy AI 国际版 Intel x86_64 安装包。已用其中的 Electron 37.10.3 Linux x64 Runtime 生成应用树和 amd64 `.deb`。构建、静态检查、原生模块冒烟检查和隔离用户目录下的 GUI 启动检查通过。

**构建成功，用户已确认现有会话可用。** 5.8.4 已替换当前用户级程序入口和原应用目录。用户确认无需重新登录即可进入并正常对话。本轮没有触发新的 Google OAuth 流程，也没有验证文件访问、内置终端、托盘或 Wayland。没有通过 dpkg 安装系统包。

## 输入与版本

| 项目 | 结果 |
|---|---|
| DMG | `WorkBuddy-darwin-x64-5.8.4.41366630-73952edb.dmg` |
| 产品 | WorkBuddy AI International，`com.workbuddy.workbuddy-ai` |
| WorkBuddy 版本 / Build ID | `5.8.4` / `73952edb48da46bd0b244661efe22f4f247c4977` |
| DMG 架构 | Intel x86_64；不是 ARM64 |
| DMG SHA256 | `8404d7eeb2653ec49ca3f3bce4b69fd101ecf60bd1fd9f8472181108a11aa63e` |
| Electron Framework | 37.10.3，来自 DMG 内 Framework 元数据 |
| Electron Linux Runtime | 37.10.3，x64，Electron Node 22.21.1，modules ABI 136，N-API 10 |
| Linux Runtime ZIP SHA256 | `c0b4edd6bd9858cda4cf7ab299e69a2d3ecd2e5fcca78507bc0851ba35614660` |
| Koffi | 2.16.2；npm 官方 SRI 已验证 |

发布探针记录在 `logs/5.8.4.41366630-73952edb/release-probe.log`。官方国际版 macOS x64 信息与本地 DMG 的版本及 SHA256 相符；当时官方 Linux DEB/RPM Feed 仍是 5.5.2。DMG 原件未改写。

## 源码与上游

- 主仓库：`No1Hoo/workbuddy-ai-linux`，HEAD `82ecae97ba5fa03e7600fb517e63086ba28d7bfa`
- 移植工具：`LX2000WASD/workbuddy-international-linux`，Commit `c2b731cf0fa566306c89697ef95c472d17525a93`
- DEB 工具：`Xboxpig/workbuddy-desktop-linux`，Commit `66103bafff518ad17a64ca34dbdbee0d2085f4a3`

未把专有 DMG、`app.asar`、用户资料或登录材料提交进 Git。构建文件与日志保留在被忽略的 `artifacts/` 和 `logs/`。

## 修改内容

- `build-latest-candidate.sh`：独立版本构建入口，默认固定本轮产品版本、Build ID、Electron 版本和摘要；路径及摘要可通过环境变量覆盖，支持 `--app-only` / `--deb-only`，按版本隔离缓存、输出和日志。
- `tools/workbuddy_prepare_new_port.py`：增加 DMG/Electron 校验、Koffi 版本与 SRI 固定、可选候选脚本路径，并避免将本机绝对 DMG 路径写入候选配置。
- `tools/workbuddy_intl_release_probe.py`：只读检查国际版发布 Feed；输出下载主机但隐藏 URL 路径及查询参数。
- `patches/port-tool-asar-grouped-unpack.patch`：将新版 ASAR 的大量部分解包项合并为分组匹配，规避 minimatch 单个模式长度上限；替换时保留回滚副本并原子写入。
- `patches/port-tool-postpatch-native-purge.patch`：转换后清除不可加载的空 `.node` 占位和外平台原生可执行文件；保留资源文件。
- `patches/port-tool-sandbox.patch`：移除启动器对 Chromium 沙盒的永久禁用参数。Kali 的 user namespace 检查成功。
- `patches/port-tool-credential-bootstrap.patch`：针对 5.8.4 新增的 Tencent 专属凭据读取 API，在 Linux 上改用 Electron `safeStorage`，并把 bootstrap 移到 `app.whenReady()` 后；密钥只以 Secret Service 加密后的形式保存，无法解密时拒绝覆盖现有材料。
- `patches/deb-tool.patch`：注册 `workbuddy-ai://` 和 `workbuddy://`；补充 `libsecret`、Ayatana 指示器、`libxss` 运行依赖；维护脚本只刷新数据库，不替用户设置默认 URI Handler。移除了 `ripgrep` 系统依赖，因为应用内已有 Linux x64 `rg`。
- `bootstrap.sh`：在独立上游目录应用上述补丁，不使用 `--force`。
- `install-user.sh`：允许 `APP_SOURCE` 指向独立候选构建；注册 MIME 类型但不修改用户 URI 默认选择。
- `.gitignore`：忽略生成的构建产物目录。

稳定版 `build.sh` 未改动。

## 兼容性检查

- 产品版本与 Electron 版本分别从 DMG 元数据确认，未把 WorkBuddy 版本误作 Electron 版本。稳定移植版与新版 Electron 都是 37.10.3，ABI 未变化。
- better-sqlite3 在 Electron ABI 136 下执行建表和参数化查询成功；Koffi Linux x64 N-API 模块成功加载；node-pty 启动 `/bin/sh` 并返回测试标记。
- 5.8.4 原始启动曾因缺少 Tencent 专属 `workbuddyStorage.loggerGet` 而报 `CREDENTIAL_BOOTSTRAP_FAILED`。补丁在 Linux 上用 Electron `safeStorage` 和 GNOME Secret Service 提供兼容材料；隔离目录启动日志不再出现该错误。
- 额外检查内置文件读写使用的是隔离临时目录，没有访问生产用户数据。
- 最终 DEB 解包后识别到 18 个 ELF，均为 x86_64；`ldd` 未发现缺失库或失败文件。最高 GLIBC 符号需求为 `GLIBC_2.42`，本机 glibc 为 2.43。
- 启动参数不含 `--no-sandbox`、`--disable-gpu-sandbox` 或 `--in-process-gpu`。TLS 校验未关闭。
- 原包有大量 ASAR 部分解包条目，已修复匹配逻辑。最终清理移除 42 个空原生占位及 14 个外平台二进制；一些作为非 Linux 预构建资源的 macOS/Windows 文件仍在资源目录中，未被 Linux 加载。
- DMG 中的国际版产品配置指向 `workbuddy-ai`；应用也包含 `workbuddy://` 内部链接。桌面入口和 MIME XML 同时登记两个 Scheme。Bundle 中还存在若干 `workbuddy.cn` 字符串字面量（共享代码资源）；本轮没有用国内版 DMG，也没有把国际版产品配置改到 `.cn`。这些共享字面量对应的运行路径未逐一验证。
- Linux x64 `rg` 位于 `resources/app.asar.unpacked/cli/vendor/ripgrep/x64-linux/rg`。DEB 不要求额外安装系统 `ripgrep`。
- macOS 专用原生功能不能视为 Linux 可用；键盘监控、macOS 通知和 Mac Framework 集成没有等价实现或没有在 Linux 验证。

## 构建与产物

构建命令（将 `DMG` 和 `NODE_BIN_DIR` 替换为本机路径；其余路径为此版本的隔离输出目录）：

```sh
NODE_BIN_DIR=/path/to/node/bin \
DMG=/path/to/WorkBuddy-darwin-x64-5.8.4.41366630-73952edb.dmg \
DMG_SHA256=8404d7eeb2653ec49ca3f3bce4b69fd101ecf60bd1fd9f8472181108a11aa63e \
APP_DIR="$PWD/artifacts/build/5.8.4.41366630-73952edb/app-credential-bootstrap-ready" \
  ./build-latest-candidate.sh --app-only
NODE_BIN_DIR=/path/to/node/bin \
DMG=/path/to/WorkBuddy-darwin-x64-5.8.4.41366630-73952edb.dmg \
DMG_SHA256=8404d7eeb2653ec49ca3f3bce4b69fd101ecf60bd1fd9f8472181108a11aa63e \
APP_DIR="$PWD/artifacts/build/5.8.4.41366630-73952edb/app-credential-bootstrap-ready" \
PKG_ROOT_OVERRIDE="$PWD/artifacts/package-root/5.8.4.41366630-73952edb-credential-bootstrap-ready" \
DIST_DIR_OVERRIDE="$PWD/artifacts/packages/credential-bootstrap-ready" \
  ./build-latest-candidate.sh --deb-only
```

- 应用树：`artifacts/build/5.8.4.41366630-73952edb/app-credential-bootstrap-ready/`，约 629 MiB。
- DEB：`artifacts/packages/credential-bootstrap-ready/workbuddy-ai_5.8.4.41366630_amd64.deb`，约 149 MiB。
- DEB SHA256：`55e5fada7887c8c0105865dfdf27f964ca7a18ecb3f054379a9eebdbd0b84aab`
- 最终应用转换日志：`logs/5.8.4.41366630-73952edb/convert-20261019-112911.log`
- 最终 DEB 构建日志：`logs/5.8.4.41366630-73952edb/deb-20261019-113041.log`
- 其他失败与重试日志均保留，便于审计和复跑。

## 验证状态

### 已验证成功

- 本地 DMG 版本、架构和 SHA256，与国际版官方 x64 发布信息一致。
- Electron Linux Runtime 版本、架构和校验值正确。
- 应用转换完成；Electron Runtime 报告 `37.10.3 / 22.21.1 / ABI 136 / x64 / linux`。
- native module 冒烟检查通过：SQLite、Koffi、OS bridge、PTY、临时文件读写。
- Xvfb 隔离目录启动时应用持续运行，国际版配置 API 返回 HTTP 200，Monaco 编辑器初始化。
- `dpkg-deb --info` / `--contents`：包名、版本及 amd64 架构正确；内容清单已保存为 `logs/5.8.4.41366630-73952edb/dpkg-contents-final.txt`。
- DEB 中 `.desktop`、MIME XML 和 shell 启动器静态检查通过；postinst 不更改 URI 默认项。
- 用户现有两个 URI Scheme 默认项均为 `workbuddy-ai.desktop`；本轮构建检查未修改它们。
- 用户级 5.8.4 已实际安装到原 `~/.local/opt/workbuddy-ai` 路径；进程结束后覆盖，启动器指向原路径。安装树与构建树校验一致。
- 安装目录中的 `resources/app.asar` 与 credential-bootstrap-ready 构建树一致（SHA256 `62da78326524de1a4cd44ef8338dfd6273b0b24611b911b0b2b6c56770df2a42`）。
- 用户在真实 Kali 桌面确认新版直接进入现有登录会话，无需重新登录，并可正常进行 AI 对话。此结果由用户实际操作确认；本轮没有读取会话材料，也没有独立查看历史列表内容。

### 仅完成构建

- `.deb` 已构建并静态验证，但没有用 dpkg 系统级安装；当前用户级安装通过 `install-user.sh` 完成。

### 需要人工测试

- 真实桌面启动、菜单/图标、系统托盘与桌面通知。
- Google OAuth 单独登录与浏览器回跳；本轮没有再次登录，因为原有会话仍有效。此前用户看到的 Google 页面没有 Chrome 工具栏，像应用内窗口，但没有采集窗口标题/网址，也没有进程级证据判定窗口归属。静态源码显示标准 WorkBuddy 授权页会经 `externalUriOpener.open()` 交给 Electron `shell.openExternal()`；Google 弹窗不在允许留在 Electron 内的域名名单中。系统 HTTP/HTTPS 默认项仍指向 Google Chrome。因此此项仍未验证，不能据此声称 OAuth 回跳已成功。
- 会话历史列表、本地文件访问、应用内终端 UI。
- GNOME Keyring / Secret Service、Wayland 与 X11 实际会话行为。
- 国际版共用代码中的 `.cn` 字符串具体是否会在特殊区域分支被调用。

### 构建失败

- 最终构建无未解决失败。早期 ASAR 匹配和 Koffi 占位问题已修复后重新构建；失败日志保留。

## 用户数据与安装状态

没有直接检查、复制、移动或删除 `~/.workbuddy-ai` 中的数据库、Token、Cookie、API Key 或会话材料。旧版是用户级安装且不在 dpkg 数据库中。用户确认旧版后台任务已结束后，检查到旧版进程为 0，随后将 5.8.4 覆盖安装到原路径 `~/.local/opt/workbuddy-ai`。安装树与构建候选树 `rsync --checksum` 比较无差异；启动器指回原路径。两个 URI 默认项仍是 `workbuddy-ai.desktop`。新版继续使用同一个 `~/.workbuddy-ai` 路径；用户随后确认仍处于有效登录态且可以对话。本轮未单独核验历史列表的具体内容。

操作记录：曾误将 `electron --version` 当作版本查询；WorkBuddy Electron 实际启动了短时间。该进程随后被停止。应用可能执行了正常启动时的配置或日志访问；没有检查其访问或写入内容，也没有读取、复制或打印登录凭据或会话数据库。
