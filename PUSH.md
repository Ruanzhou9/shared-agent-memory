# 推送到 GitHub 操作清单

本仓库内容已就绪、隐私自检已通过。等待你网页建仓后我来推送，或你自行执行（见下）。

## 你要做的一步（网页建仓）
1. 打开 https://github.com/new
2. 填 Repository name（例如 `shared-agent-memory` 或 `agent-memory-skill`）
3. Visibility 选 **Public**
4. 不要勾选 "Add a README file" / ".gitignore" / "LICENSE"（仓库已有，避免冲突）
5. 点 **Create repository**

## 我推送需要的下一步输入
建好后把仓库地址发我即可。两种地址之一都行：
- HTTPS: `https://github.com/你的用户名/仓库名.git`
- SSH:   `git@github.com:你的用户名/仓库名.git`（需你配置过 SSH key）

> 注：当前机器未配 gh / GitHub 认证 / SSH key，所以 HTTPS 推送需要你在浏览器里授权
> （git 会弹窗让你登录 GitHub，或用 token）。或者告诉我用户名+仓库名，我给出带 token 的确切命令。

## 若你要自行推送（可选）
在仓库根目录执行：
```
git remote add origin <仓库地址>
git branch -M main
# 推送前务必先跑隐私自检
bash scripts/pre-push-check.sh
# 然后推送
git push -u origin main
```

## 已就绪状态
- git 仓库已初始化，3 次干净提交，作者为中性匿名（不泄漏真实身份）
- `scripts/pre-push-check.sh` 通过（退出码 0）
