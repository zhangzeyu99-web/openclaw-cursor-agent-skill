# Task Prompt Structure

Use this prompt shape when `spawn-cursor.sh` auto-generates a task file or when the user asks for a reusable prompt template.

# OpenClaw Cursor 任务

## 基本信息
- 任务 ID: {{TASK_ID}}
- 会话名: {{SESSION_NAME}}
- 项目路径: {{PROJECT_PATH}}
- 创建时间: {{CREATED_AT}}
- 优先级: {{PRIORITY}}
- 预计耗时: {{ETA}}

## 任务描述
{{TASK_DESCRIPTION}}

## 角色
你是 Cursor CLI Agent，通过 tmux 会话接收来自 OpenClaw 的任务。请先阅读相关代码，再按项目现有架构完成需求。

## 执行要求
1. 先理解项目结构和已有实现。
2. 遵循项目规范和命名约定。
3. 修改前说明计划，过程中持续输出进度。
4. 遇到阻塞时说明问题、尝试方案和需要的决策。
5. 完成后总结文件改动、测试结果和后续建议。

## 标准输出格式
开始任务时输出：
```
============================================================
开始执行: {{TASK_NAME}}
工作目录: {{PROJECT_PATH}}
预计耗时: {{ETA}}
============================================================
```

完成步骤时输出：
```
已完成步骤 N: [步骤名称]
耗时: [X 分钟]
产出: [简要说明]
```

遇到问题时输出：
```
遇到问题: [问题描述]
详情: [详细说明]
尝试方案:
1. [方案一]
2. [方案二]
建议: [需要用户决策的内容]
```

任务完成时输出：
```
============================================================
任务完成: {{TASK_NAME}}
总耗时: [总时间]
完成清单:
- [子任务]
修改文件:
- [文件路径]
测试结果:
- [测试摘要]
备注:
- [补充说明]
============================================================
```

## 控制指令
- /pause
- /resume
- /status
- /focus [子任务]
- /expand [新增需求]
- /abort [原因]

## Notes

- Keep the prompt short enough to fit comfortably in the CLI context window.
- Put project-specific acceptance criteria into the generated task file, not the skill itself.
- Prefer a single task file per session so the run remains auditable.
