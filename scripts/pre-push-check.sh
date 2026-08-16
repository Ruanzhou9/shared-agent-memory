#!/usr/bin/env bash
# ============================================================
# Pre-push 隐私自检脚本：提交/推送前运行，防止个人信息泄漏。
# 用法:  bash scripts/pre-push-check.sh   (在仓库根目录运行)
# 退出码: 0=干净可推送, 1=检测到疑似泄漏(不允许推送)
# ============================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LEAK=0
say_ok(){ echo "  ✓ $1"; }
say_bad(){ echo "  ⚠️  $1"; LEAK=1; }

echo "══ 共享 Agent Memory 开源仓库 · 隐私自检 ══"
echo ""

# 1. 真实身份 / 邮箱 / 用户名  (排除脚本自身——它含这些关键词作为搜索模式)
if grep -rniE "bhwcy|eeph@|@126\.com|Ruanzhou9" --include='*' . 2>/dev/null | grep -v '^\./\.git/' | grep -v '^\./scripts/pre-push-check.sh:'; then
  say_bad "[身份/邮箱/用户名] 疑似命中真实身份信息"
else
  say_ok "[身份/邮箱/用户名] 无"
fi

# 2. 绝对用户路径 /Users/
if grep -rn "Users/" . 2>/dev/null | grep -v '^\./\.git/' | grep -v '^\./scripts/pre-push-check.sh:'; then
  say_bad "[绝对路径] 命中 /Users/..."
else
  say_ok "[绝对路径] 无"
fi

# 3. 凭证 / 密钥
if grep -rniE "sk-[A-Za-z0-9]{16}|api[_-]?key[=:][[:space:]]*[A-Za-z0-9]{12}|AKIA[0-9A-Z]{10}|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY" --include='*' . 2>/dev/null | grep -v '^\./\.git/' | grep -v '^\./scripts/pre-push-check.sh:'; then
  say_bad "[凭证/密钥] 疑似命中真实密钥"
else
  say_ok "[凭证/密钥] 无"
fi

# 4. 个人生活痕迹(项目相关本地路径/软件习惯, 可按需增删)
if grep -rniE "voice-clone|local-ai-doctor|obsidian-content-capture|douyin|wechat|抖音|微信" --include='*' . 2>/dev/null | grep -v '^\./\.git/' | grep -v '^\./scripts/pre-push-check.sh:'; then
  say_bad "[个人项目/习惯] 命中可识别项目或使用痕迹"
else
  say_ok "[个人项目/习惯] 无"
fi

# 5. git 提交作者是否泄漏真实身份
echo ""
echo "══ git 提交作者检查 ══"
if git log --format='%an <%ae>' 2>/dev/null | grep -iE "bhwcy|eeph|Ruanzhou9|@126\.com"; then
  say_bad "[git 作者] 提交历史含真实身份!"
else
  say_ok "[git 作者] 提交历史为中性作者"
fi

echo ""
if [ "$LEAK" -eq 0 ]; then
  echo "✅ 全部通过，可安全提交/推送。"
fi
echo ""
exit $LEAK
