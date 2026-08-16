<div align="center">

# 🧠 Shared Agent Memory Skill

**让任意 agent 共享同一份长期记忆 —— 跨会话、跨 agent 自动沉淀与复用**

一个**通用、去平台化**的 Agent 记忆库 Skill。无论你用 Codex、Claude Code、Hermes、OpenClaw、
OpenCode、Cursor 还是各类 Harness，只要它读取标准 `SKILL.md`，就能加载并共享这份记忆。

**"每个 agent 都记住你是谁、你怎么做事，你不用每次重说一遍。"**

</div>

---

## 🎯 它解决什么问题

使用 Agent 时，最让人烦躁的一点是：**换个会话、换一个 Agent，就要重新交代自己的偏好、背景和做事方式。**

- 项目背景讲过一遍，不该每个 agent 从零重读。
- 一套方法已经跑通，不该下次再摸索一遍。
- 你的个人偏好与处理风格，不该每个工具各记一版。

本项目把"你希望所有 agent 记住的东西"沉淀成**一份共享记忆库**，任何 agent 在发起任务时
都按同一套协议读取它、并在对话中自动把新的稳定偏好写回去——**一次沉淀，全部复用。**

---

## 🏗️ 架构总览

<img src="./docs/architecture.svg" width="100%" alt="Architecture overview">

> 多个 agent 读取同一份 `SKILL.md` 协议，读写同一份 Markdown 记忆库；用户只维护一份，
> 所有 agent 共享。

---

## 📚 设计参考：分层记忆处理模式

本项目的处理思路借鉴了开源项目
**[TencentDB Agent Memory](https://github.com/TencentCloud/TencentDB-Agent-Memory)** 的
"分层记忆"设计：把对话按 **L0 → L1 → L2 → L3** 逐层提炼，只把精华喂回给 agent，
而不是把原始聊天一股脑塞回去——这样既共享记忆，又省 Token。

<img src="./docs/memory-pipeline.svg" width="100%" alt="Layered memory pipeline">

### 分层模型对照

| 层级 | 含义 | 本项目落地 |
|---|---|---|
| **L0 · 原始对话** | 与 agent 的聊天记录 | 只存"一句话摘要 + 会话日志指针"，原文留在各自 agent 的会话存档，**不进库** |
| **L1 · 原子记忆** | 一条条稳定的偏好 / 事实 / 处理方式 | `memory/atoms/*.md`，一条一文件，带 `type / priority` 门控 |
| **L2 · 场景块** | 多个原子围绕同一上下文凝聚成的经验 | `memory/scenes/*.md`，含 `summary:` 索引，按需读取 |
| **L3 · 用户画像** | 跨领域的稳定偏好与风格 | `memory/persona.md`，每次会话读取的核心（≤ 3 KB） |

> **与 TencentDB-Agent-Memory 的区别**：Tencent 那套是完整的多组件服务（含 Proxy、知识库、
> 云端存储），本仓库刻意做成**极简、单一 `SKILL.md` + 一个 Markdown 文件夹、零外部依赖**，
> 目的是"拷进任意 agent 的技能目录即可用"，而不是再部署一套服务。

---

## ✨ 特性

- **通用格式**：标准 `SKILL.md` + Markdown 记忆库，任何读 `SKILL.md` 的 agent 都能加载。
- **跨会话 / 跨 agent 共享**：同一份记忆库被不同会话、不同 agent 读取。
- **省 Token**：每次会话只注入 persona + 命中当前任务的高优先原子记忆，绝不灌全量历史；
  原始聊天永不进库；persona 硬阈值 ≤ 3 KB。
- **自动沉淀**：agent 按协议把对话中稳定的偏好提炼成原子记忆，并自动去重、逐层归并到画像。
- **自托管 / 可同步**：记忆库就是普通 Markdown 文件夹，可放本地、同步到你的 Obsidian vault
  或 git 仓库。
- **无平台锁定**：不依赖任何特定 Harness，移走即用。

---

## 🚀 快速开始

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

> **快速校验**：新开会话，问你的 agent"是否加载了 shared-agent-memory"。若未出现，
> 确认 `SKILL.md` 首行为 `---`、文件名正确，并重启 agent / 新开会话。

---

## 📁 目录结构

```
shared-agent-memory/
├── SKILL.md                 # 记忆库读写协议（agent 自动加载的入口）
└── memory/
    ├── persona.md           # L3 用户画像（每次会话读取的核心，≤3KB）
    ├── atoms/*.md           # L1 原子记忆（一条一个文件，带 schema）
    ├── scenes/*.md          # L2 场景块
    └── chat-log/*.md        # L0 聊天记录摘要/指针（不进原文）
```

### 原子记忆的 schema 示例

```markdown
---
type: preference | fact | handling | constraint
priority: 1-10      # 越高越重要，主动注入；<=4 仅供按需检索
tags: [可选, 标签]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
<一句话核心声明>
<可选：一两行补充/由来/示例>
```

`memory/atoms/_template.md` 提供了可直接复制的模板。

---

## ⚙️ 工作原理（TL;DR）

1. **读取**：新会话开始时，agent 读 `persona.md` + 命中当前任务的高优先原子记忆。
2. **写入**：对话中出现稳定的偏好 / 事实 / 处理方式时，按 schema 写原子记忆。
3. **归并**：积累过多时，agent 自动去重、把 2+ 次验证的偏好升到 persona、把过期项降级/删除。

**省 Token 铁律**（详见 `SKILL.md`）：
原始聊天不进库；每次只读 persona + 命中的高优先原子；persona ≤ 3 KB 且超限即压缩；
绝不自动通读全量历史。目标：每次会话自动注入内容恒在 ~1–1.5 KB 内。

---

## 🔁 如何同步 / 备份

记忆库就是普通文件夹，同步方式随你喜欢：

- **Obsidian**：把 `shared-agent-memory/memory/` 软链进你的 vault，即可在 Obsidian 里查看 / 编辑。
- **git**：直接把这个仓库 clone 下来，用 git 管理记忆内容的版本与备份。
- **私有使用**：若记忆含个人信息，请用私有仓库存放 `memory/`，不要推到公开仓库。

---

## 🛡️ 隐私 & 安全

- 本仓库默认 **不含任何真实用户的个人信息**，记忆库以空模板发布。
- **请勿**把含个人真实身份信息（用户名、真实邮箱、绝对路径、凭证）提交到公开仓库。
- 仓库自带 `scripts/pre-push-check.sh` 隐私自检脚本；推送前跑一遍可拦截常见的身份/路径/密钥泄漏。

```bash
bash scripts/pre-push-check.sh   # 退出码 0 表示可安全推送
```

---

## 📄 License

[MIT](LICENSE)

---

<div align="center"><em>Made for anyone who wants their agents to remember — across sessions, across agents.</em></div>
