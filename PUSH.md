# 推送到 GitHub · 终端操作清单

仓库内容已就绪（README + 图片 + 隐私自检通过），origin 已指向：
`https://github.com/Ruanzhou9/shared-agent-memory.git`

## 在你本机终端执行以下命令完成推送

```bash
cd /Users/a/dsh-desktop/agent-memory-skill

# 1) 先跑隐私自检（确认无个人身份/路径/凭证泄漏）
bash scripts/pre-push-check.sh

# 2) 配置认证（三选一）：
#    a) 用 token：先到 https://github.com/settings/tokens 生成一个有 repo 权限的 token
#       git config --global credential.helper osxkeychain
#       git push -u origin main   # 会提示输入用户名(Ruanzhou9)和 token
#    b) 用 SSH（需先配好 ~/.ssh/id_ed25519 并添加到 GitHub）: 把 remote 改回
#       git remote set-url origin git@github.com:Ruanzhou9/shared-agent-memory.git
#       git push -u origin main

# 3) 推送主分支
git branch -M main
git push -u origin main
```

推送成功后：
- 公开访问：https://github.com/Ruanzhou9/shared-agent-memory
- README 渲染两张图：docs/architecture.svg、docs/memory-pipeline.svg

## 如果要加 Topics（帮助搜索曝光，仓库页右侧）
建议：`agent skills` `memory` `llm` `ai` `claude-code` `codex` `ai-tools` `open-source`
（在仓库页 Settings / 或网页右侧 Topics 处添加）
