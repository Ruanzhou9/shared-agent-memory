# Shared Agent Memory Skill

一个**通用、去平台化**的跨会话 Agent 记忆库 Skill。让不同的 agent（Codex / Claude Code /
Hermes / OpenClaw / OpenCode / Cursor / 各类 Harness）**共享同一份长期记忆**：个人偏好、
处理方式、经验事实，跨会话自动沉淀与复用，用户不必每次重复描述自己。

借鉴分层记忆的思路（L0 原始对话 → L1 原子记忆 → L2 场景 → L3 画像 → 跨会话注入），
但以**标准 `SKILL.md` 格式**落地，**不依赖任何特定 Harness**，放进任意支持 agent skill
的目录即可用。

## 特性

- **通用格式**：一份 `SKILL.md` + Markdown 记忆库，任何读 `SKILL.md` 的 agent 都能加载。
- **跨会话 / 跨 agent 共享**：同一份记忆库被不同会话和不同 agent 读取。
- **省 Token**：只在每次会话注入 persona + 命中当前任务的高优先原子记忆，不灌全量历史；
  原始聊天永远不进库；persona 硬阈值 ≤ 3 KB。
- **自动沉淀**：agent 按协议在对话中提炼稳定偏好写入原子记忆，并自动去重、逐层归并到画像。
- **可自托管**：记忆库就是普通 Markdown 文件夹，可放在本地、同步到你的 Obsidian vault 或 git 仓库。

## 快速开始

```bash
# 1. 克隆 / 拷贝本仓库
git clone <repo-url> agent-memory-skill
cd agent-memory-skill

# 2. 把 shared-agent-memory 放进你用的 agent 技能根目录（按你用的 agent 选其一）：
#    Codex:        ~/.codex/skills/
#    Claude Code:  ~/.claude/skills/  或 项目 .claude/skills/
#    Hermes:       ~/.hermes/skills/
#    OpenClaw:     ~/.openclaw/skills/
#    OpenCode:     ~/.config/opencode/…/skills
#    Cursor:       项目 .cursor/skills/
#    Harness:      ~/.dsh/skills/  或 项目 skills/

# 3. 编辑 memory/persona.md 和 memory/atoms/，填成你自己的偏好和事实（清空模板）。
```

> 快速校验：新开会话，问 agent"是否加载了 shared-agent-memory"。若未出现，确认 `SKILL.md`
> 首行为 `---`、文件名正确，并重启 agent / 新开会话。

## 目录结构

```
shared-agent-memory/
├── SKILL.md                 # 记忆库读写协议（agent 自动加载的入口）
└── memory/
    ├── persona.md           # L3 用户画像（每次会话读取的核心，≤3KB）
    ├── atoms/*.md           # L1 原子记忆（一条一个文件，带 schema）
    ├── scenes/*.md          # L2 场景块
    └── chat-log/*.md        # L0 聊天记录摘要/指针（不进原文）
```

## 工作原理（TL;DR）

1. **读取**：新会话开始时，agent 读 `persona.md` + 命中任务的高优先原子记忆。
2. **写入**：对话中出现稳定的偏好/事实/处理方式时，按 schema 写原子记忆。
3. **归并**：过度积累时，agent 自动去重、把 2+ 次验证的偏好升到 persona、把过期项降级/删除。

详见 [`shared-agent-memory/SKILL.md`](shared-agent-memory/SKILL.md)。

## 隐私 & 安全

- 本仓库默认不含任何真实用户的个人信息，记忆库以空模板发布。
- **请勿**把含个人真实身份信息（用户名、真实邮箱、绝对路径、凭证）的内容提交到公开仓库。
- 若要在团队/公开使用，请把 `memory/` 换成你自己的匿名化内容，或分叉维护私有记忆。

## License

[MIT](LICENSE)

---

_Made for anyone who wants their agents to remember — across sessions, across agents._
