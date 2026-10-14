---
type: preference | fact | handling | constraint
priority: 1-10            # 主字段：注入优先级；>=6 主动注入，<=4 仅供按需检索
confidence: (可选 0-1)     # 内容可信度，与 priority 正交；高>=0.85 / 中0.6-0.84 / 低<0.6
status: (可选)             # candidate | active | user-accepted | superseded | archived
source: (可选)             # 溯源：<agent-slug>@<host>，如 workbuddy@mac-m3
verified: (可选 YYYY-MM-DD) # 最近一次确认仍成立的日期；priority>=6 建议填写
tags: [可选, 标签]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
原子记忆模板（复制本文件改名后使用，不要把本文件当作记忆）。
type 取 preference / fact / handling / constraint；
priority >=6 会主动注入，<=4 仅供按需检索；
status 非 active / user-accepted 时不得当作已定结论。
正文保持一两句话；同义条目先 grep 查重再合并，勿重复建文件。
新建记忆建议先落到 memory/inbox/<你的 agent-slug>/ 作为候选，晋升时再移入本目录。
