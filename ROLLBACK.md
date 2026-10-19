# 回滚说明

用户要求不备份旧版程序，因此 5.5.2 程序目录已由 5.8.4 覆盖，且没有制作旧版副本。`~/.workbuddy-ai` 用户资料不属于应用程序目录，本轮未复制、清理或移动。

如果 5.8.4 覆盖后无法启动：

1. 先退出 WorkBuddy AI。
2. 重新取得 5.5.2 对应的 WorkBuddy 国际版 DMG，并使用原有稳定版构建来源重新生成应用树。旧版二进制没有保留在本工作目录中，所以回滚不是即时切换。
3. 将生成的应用树重新安装到用户级目录：

   ```sh
   APP_SOURCE=/path/to/5.5.2/app ./install-user.sh
   ```

   该步骤会覆盖 `~/.local/opt/workbuddy-ai` 的程序文件，但保留现有用户资料目录。

4. 启动 `workbuddy-ai`，由你人工确认登录和历史状态。

本次 5.8.4 的构建日志、DEB 和应用树保留在本仓库 `logs/` 与 `artifacts/`。如果改用系统级 DEB 安装，可通过 `sudo dpkg -r workbuddy-ai` 移除系统包；该操作不移除 `~/.local/opt/workbuddy-ai` 用户级安装。

不要为了回滚删除 `~/.workbuddy-ai`，也不要用旧版本启动后执行任何清理用户资料的操作。
