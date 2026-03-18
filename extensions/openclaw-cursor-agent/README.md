# OpenClaw Cursor Agent Plugin

这是 `cursor-agent-system` 的 OpenClaw 插件化封装。安装后，OpenClaw 可以通过工具、聊天命令和 CLI 命令管理 `tmux + Cursor CLI` 后台任务。

## 功能

- 注册 6 个 OpenClaw 工具：
  - `cursor_agent_spawn_task`
  - `cursor_agent_list_tasks`
  - `cursor_agent_check_status`
  - `cursor_agent_send_command`
  - `cursor_agent_kill_session`
  - `cursor_agent_doctor`
- 注册聊天命令 `/cursor`
- 注册 CLI 命令：
  - `openclaw cursor-agent-doctor`
  - `openclaw cursor-agent-list`
- 内置一个配套 Skill，方便 Agent 自动命中这套后台任务架构

## 依赖

- `cursor-agent-system/` 工具目录
- `tmux`
- `agent` 或 `cursor-agent`
- Linux / WSL 环境中的 `bash`

## 关键配置

插件运行主要依赖下面几个配置项：

- `toolkitRoot`: `cursor-agent-system` 的绝对路径
- `defaultProjectPath`: 默认项目路径
- `executionMode`: `direct` 或 `wsl`
- `shell.executable`: 例如 `bash` 或 `C:/Windows/System32/wsl.exe`
- `shell.args`: 额外参数
- `shell.wslDistro`: 可选，指定 WSL 发行版

## 聊天命令

```text
/cursor doctor
/cursor list
/cursor status <会话名>
/cursor send <会话名> <指令>
/cursor kill <会话名> [--force]
/cursor spawn <任务名> || <任务描述> || [项目路径]
```

## 适用场景

当你希望 OpenClaw：

- 后台持久化跑长时编码任务
- 随时查看进度
- 中途追加新指令
- 在任务完成后做统一清理

就应该启用这个插件，而不是直接让 OpenClaw 调用无 TTY 的 Cursor CLI。

## Windows 说明

当前仓库环境是 Windows PowerShell，但这套架构本质仍依赖 `tmux`。因此推荐：

1. 在 Windows 上安装并启用 WSL
2. 在 WSL 里安装 `tmux` 与 Cursor CLI
3. 将插件配置为 `executionMode: "wsl"`

如果本机还没有 `wsl.exe`，安装脚本会保留插件文件并给出警告，但不会假装运行成功。
