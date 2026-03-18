# OpenClaw Cursor Agent Skill

`OpenClaw Cursor Agent Skill` 是一套把 `OpenClaw -> tmux -> Cursor CLI` 串起来的后台任务架构，已经封装成：

- 一个可安装的 OpenClaw 插件
- 一个可让 OpenClaw 学习并自动使用的 Skill
- 一套可独立运行的 `cursor-agent-system` 工具脚本
- 一份适配 Windows 当前环境的 PowerShell 安装脚本

这套方案的核心目标是：让 OpenClaw 能把长时间编码任务交给 Cursor CLI 在 `tmux` 里持久运行，而不是只做短平快的单轮任务。

## 它有什么能力

### 1. 后台持久化编码任务

OpenClaw 可以启动一个真正跑在 `tmux` 里的 Cursor CLI 会话，让任务在后台持续执行，不依赖当前聊天会话存活。

### 2. 实时任务监控

可以查看：

- 当前会话是否还活着
- tmux pane PID
- 最近输出内容
- 状态文件里的进度信息

### 3. 运行中追加指令

任务开始后，你还可以继续发控制指令，例如：

- `/pause`
- `/resume`
- `/status`
- `/focus 某个子任务`
- 普通补充说明，比如“改成 RS256”

### 4. 优雅终止与清理

可以先尝试 `Ctrl+C` 优雅终止，如果失败再强制 kill，还可以选择是否清理状态文件、任务文件和日志文件。

### 5. Skill 化复用

仓库里的插件自带 Skill，OpenClaw 安装后可以学习这套架构，并在需要后台持久任务时自动使用合适的工具与命令。

### 6. 兼容当前 Windows 场景

当前仓库额外附带了 PowerShell 安装脚本，适配你现在的 Windows 环境。  
安装脚本现在支持两条路线：

- 优先 `WSL`
- 如果没有 `wsl.exe`，自动降级到 `Git for Windows + Git Bash` 兼容模式

在 Git Bash 兼容模式下，安装脚本会自动完成这些额外动作：

- 安装 Windows 原生 `Cursor CLI`
- 给 Git Bash 注入 `agent` / `cursor-agent` / `python3` 包装入口
- 下载并写入与 Git for Windows 兼容的 `tmux` 运行文件
- 初始化 `status/`、`tasks/`、`logs/` 运行目录

## 仓库结构

```text
.
├── README.md
├── install-openclaw-cursor-agent.ps1
├── cursor-agent-system/
│   ├── README.md
│   ├── scripts/
│   ├── templates/
│   ├── status/
│   ├── tasks/
│   └── logs/
├── extensions/
│   └── openclaw-cursor-agent/
│       ├── openclaw.plugin.json
│       ├── index.js
│       ├── README.md
│       ├── skill/
│       └── examples/
└── .cursor/
    └── skills/
        └── openclaw-cursor-agent-system/
```

## 主要组成

### A. `cursor-agent-system`

这是底层脚本工具包，提供 5 个核心脚本：

- `spawn-cursor.sh`
- `check-status.sh`
- `attach-session.sh`
- `send-command.sh`
- `kill-session.sh`

这些脚本负责真正和 `tmux + Cursor CLI` 打交道。

### B. `extensions/openclaw-cursor-agent`

这是 OpenClaw 插件层，负责把上面的 Bash 工具包包装成 OpenClaw 可直接调用的能力。

插件注册了这些工具：

- `cursor_agent_spawn_task`
- `cursor_agent_list_tasks`
- `cursor_agent_check_status`
- `cursor_agent_send_command`
- `cursor_agent_kill_session`
- `cursor_agent_doctor`

插件还注册了这些聊天命令：

- `/cursor doctor`
- `/cursor list`
- `/cursor status <会话名>`
- `/cursor send <会话名> <指令>`
- `/cursor kill <会话名> [--force]`
- `/cursor spawn <任务名> || <任务描述> || [项目路径]`

### C. Skill

插件内置了 Skill：

- `extensions/openclaw-cursor-agent/skill`

另外仓库还保留了一份 Cursor 本地 Skill 版本：

- `.cursor/skills/openclaw-cursor-agent-system`

前者给 OpenClaw 学，后者给 Cursor 学。

## 这个插件怎么使用

### 方式 1：作为 OpenClaw 插件使用

先安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cursor-agent.ps1
```

安装完成后，常用入口有两类。

#### 1. 聊天命令

```text
/cursor doctor
/cursor list
/cursor status myproj-auth-20260318-180000
/cursor send myproj-auth-20260318-180000 /status
/cursor send myproj-auth-20260318-180000 把 JWT 改成 RS256
/cursor kill myproj-auth-20260318-180000 --force
/cursor spawn feature-auth || 实现 JWT 登录接口 || D:/project/openclaw
```

#### 2. OpenClaw 工具调用

当 Agent 自动规划时，可以直接使用这些工具：

- `cursor_agent_spawn_task`
- `cursor_agent_check_status`
- `cursor_agent_send_command`
- `cursor_agent_kill_session`

推荐工作流：

1. 先调用 `cursor_agent_doctor` 检查环境。
2. 用 `cursor_agent_spawn_task` 启动后台任务。
3. 用 `cursor_agent_check_status` 轮询。
4. 中途用 `cursor_agent_send_command` 追加新要求。
5. 完成后用 `cursor_agent_kill_session` 收尾。

### 方式 2：直接使用脚本工具包

进入：

```bash
cd cursor-agent-system
```

启动任务：

```bash
./scripts/spawn-cursor.sh \
  feature-auth \
  "实现 JWT 登录接口并补充测试" \
  /path/to/project \
  --priority high \
  --eta 45分钟
```

查看状态：

```bash
./scripts/check-status.sh
./scripts/check-status.sh feature-auth
```

发送指令：

```bash
./scripts/send-command.sh myproj-feature-auth-20260318-180000 "/status"
./scripts/send-command.sh myproj-feature-auth-20260318-180000 "把 JWT 改成 RS256"
```

结束任务：

```bash
./scripts/kill-session.sh myproj-feature-auth-20260318-180000 --force
```

## 环境要求

### 推荐环境

- Windows + WSL
- 或 macOS / Linux

### 必需依赖

- `tmux`
- `agent` 或 `cursor-agent`
- `python3`
- `bash`

### 当前 Windows 环境说明

这套架构依赖 `tmux`，而 `tmux` 不能在普通 Windows PowerShell 里直接作为 OpenClaw 后台会话层使用。

当前仓库的安装脚本已经做了兼容处理：

1. 如果系统有 `wsl.exe`，默认走 `WSL`
2. 如果没有 `wsl.exe`，但检测到 `Git for Windows`，则自动走 `direct + Git Bash`
3. 如果两者都没有，插件文件仍会安装，但默认保持禁用

因此在 Windows 上，推荐优先顺序是：

- `WSL`
- `Git Bash 兼容模式`
- 最后才是手动补环境

## 安装脚本做了什么

`install-openclaw-cursor-agent.ps1` 会：

1. 把插件复制到 `~/.openclaw/workspace/plugins/openclaw-cursor-agent`
2. 把 `cursor-agent-system` 复制到 `~/.openclaw/workspace/cursor-agent-system`
3. 尝试更新你的 `openclaw.json`
4. 自动探测 `wsl.exe`、`git.exe`、`bash.exe`
5. 在 Git Bash 模式下自动补 `tmux`、`agent`、`python3` 兼容层
6. 初始化运行目录
7. 如果系统还不能执行这套架构，就先把插件设为 `disabled`

## 配置示例

Windows 示例配置见：

- `extensions/openclaw-cursor-agent/examples/openclaw.json.windows.example.json`

## 适用场景

这套方案特别适合：

- 长时间重构任务
- 需要 IDE/工作区上下文的复杂开发任务
- 希望后台跑多个 Cursor 编码任务
- 希望运行过程中不断追加需求
- 希望 OpenClaw 具备“调度一个持久编码代理”的能力

## 当前限制

- 没有 `bash` / `wsl` / `tmux` 时，插件只能安装，不能真正执行后台任务
- Windows 原生 PowerShell 不能直接替代 tmux
- 当前仓库更偏“单机任务调度”，还没有做成分布式任务编排系统

## 下一步建议

如果你希望把它用于正式环境，推荐继续补三项：

1. WSL 自动安装与环境探测
2. 任务超时和自动回收
3. 任务完成通知和失败告警
