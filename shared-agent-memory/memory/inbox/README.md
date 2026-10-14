# 候选记忆收件箱（inbox）

**新沉淀的记忆先进这里，不要直接写 `atoms/` / `persona.md`。**

## 为什么要有这一层

多个 agent（WorkBuddy / Codex / Hermes / Claude Code …）可能同时往记忆库写东西。
如果大家都直接改同一份 `atoms/`，就会互相覆盖——「更新静默丢失」是共享记忆最隐蔽也最贵的坑。

inbox 用**文件归属**从构造上消灭冲突：

- 每个 agent 只写自己的子目录，**代号必须带主机后缀**：
  `inbox/<agent-slug>-<host>/`，例如 `workbuddy-mac-m3`、`codex-win-pc`、`hermes-mac-m3`。
  ⚠️ 只用 `inbox/workbuddy/` 是不够的——同一个 agent 装在两台机器上会写进同一个目录；
  实测：两台机器在同代号目录下写同名候选，`git merge` **会冲突**（换成带主机后缀的代号则不冲突）。
- 候选文件名再带日期前缀：`<YYYY-MM-DD>-<主题>.md`（如 `2026-10-14-prefers-bullet.md`），
  作为第二道保险。
- 谁都不改别人的文件；想改别人的记忆 → 先读，保留双方版本，把合并建议写进自己的 inbox。
- 因为各写各的文件，**git 按文件合并，冲突天然不会出现**（跨设备同步因此成立）。

## 候选文件格式

与原子记忆同 schema（`type` / `priority` / `confidence` / `status` / `source` / `verified` /
`tags` / `created` / `updated`），`status` 通常为 `candidate`：

```markdown
---
type: preference
priority: 6
status: candidate
source: workbuddy@mac-m3
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
一句话核心声明。
```

## 候选如何晋升

由**归并协议**统一执行（见 `SKILL.md` 的「归并 / 总结压缩协议」）：

1. 用户确认，或候选被 2+ 次独立会话验证；
2. **晋升是单写者操作**：先 `git pull --rebase` 且工作区干净 → 把候选写入 `atoms/`（补齐 `verified`）
   → 从 inbox 删除该文件 → commit → push。push 被拒就先 rebase 重试，**不要强推**；
3. 多台设备同时想晋升 → **后到的一方本轮只 push 自己的 inbox 候选**，下轮再晋升。
   并行改 `persona.md` 必然冲突（实测确认）；
4. 某 agent 的 inbox 超过 10 条时触发一次晋升评估。

## 冲突暂存

多设备同步真的撞上 `<<<<<<<` 时，把双方原文挪到 `inbox/<agent-slug>/conflicts/` 保留，
由用户裁决；**禁止**自动挑一方，也**禁止**把冲突标记留在 `atoms/` / `persona.md` 里。

## 不注入

`inbox/` 整体**不属于记忆**，任何会话都不许把 inbox 内容当作已确认记忆注入上下文。
