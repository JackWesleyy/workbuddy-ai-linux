# 安装 WorkBuddy AI International 5.8.4

## 当前 Kali 的用户级安装

当前 5.8.4 已安装在 `~/.local/opt/workbuddy-ai`，`~/.local/bin/workbuddy-ai` 启动器指向此处。下列命令可重复部署本次候选应用：

```sh
APP_SOURCE="$PWD/artifacts/build/5.8.4.41366630-73952edb/app-credential-bootstrap-ready" \
  ./install-user.sh
```

这会替换 `~/.local/opt/workbuddy-ai` 中的程序文件，并刷新该用户的启动器、桌面入口、图标和 MIME 数据。它不会复制、清理或重建 `~/.workbuddy-ai`。脚本也不会修改 `xdg-mime` 的默认 Scheme Handler。安装前应先退出 WorkBuddy，以免后台子进程继续读取被替换的文件。

如果旧版还在运行，可使用 `APP_DIR_NAME=workbuddy-ai-5.8.4.41366630` 先安装到独立目录并切换后续启动入口；待旧进程结束后再按需清理旧目录。本轮在旧进程结束后已直接覆盖原目录。

启动方式：

```sh
workbuddy-ai
```

如果 shell 的 `PATH` 未含 `~/.local/bin`，使用 `~/.local/bin/workbuddy-ai`。

## DEB

可分发的包位于：

```text
artifacts/packages/credential-bootstrap-ready/workbuddy-ai_5.8.4.41366630_amd64.deb
```

查看包信息和内容：

```sh
dpkg-deb --info artifacts/packages/credential-bootstrap-ready/workbuddy-ai_5.8.4.41366630_amd64.deb
dpkg-deb --contents artifacts/packages/credential-bootstrap-ready/workbuddy-ai_5.8.4.41366630_amd64.deb
```

系统级安装会写入 `/opt/workbuddy-ai` 和 `/usr`，需要 root 权限；它不会替换现有的 `~/.local` 程序。此包未在本轮以 dpkg 安装。

## URI Scheme

包和用户桌面入口都声明 `workbuddy-ai://` 与 `workbuddy://`。本机原有默认 Handler 已指向 `workbuddy-ai.desktop`，本轮没有更改默认项。若在其他桌面环境首次安装，按需在系统设置中为两个 Scheme 选择 WorkBuddy AI。

## Google 登录

标准国际版登录源码把 WorkBuddy 授权页交给桌面默认浏览器。用户反馈 Google 登录页面看起来像应用内窗口；目前尚未确认窗口实际所属进程，因此在确认它确由系统浏览器打开前，请不要在该页面输入凭据。登录和回跳仍需人工验证。
