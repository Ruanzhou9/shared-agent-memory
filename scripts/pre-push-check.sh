#!/usr/bin/env bash
# ============================================================
# Pre-push 隐私自检脚本：提交/推送前运行，防止个人信息泄漏。
#
# 用法:  bash scripts/pre-push-check.sh
# 退出码: 0=干净可推送, 1=检测到疑似泄漏(不允许推送)
#
# 设计要点（v2）：
#  1. 内置的只放【通用模式】（密钥格式、家目录路径、PII），可公开、不泄密；
#  2. 用户专属身份/项目黑名单放 scripts/blacklist.local（已 gitignore，不入库），
#     —— 早期版本把真实邮箱/用户名写在本脚本里，等于用泄漏的方式防泄漏；
#  3. 所有模式写成「正则字面量」形式（[/]Users[/] 等），本文件不会匹配到自身，
#     不再依赖「按路径排除自己」这种改名即失效的脆弱做法。
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

SELF="$(basename "$0")"
BL_FILE="scripts/blacklist.local"
LEAK=0

say_ok(){  echo "  ✓ $1"; }
say_bad(){ echo "  ⚠️  $1"; LEAK=1; }
say_skip(){ echo "  – $1"; }

# 统一排除：git 元数据、本脚本自身、本地黑名单文件
GREP_EXCLUDES=(--exclude-dir=.git --exclude="${SELF}" --exclude="blacklist.local"
               --exclude-dir=node_modules --exclude-dir=.venv)

echo "══ 共享 Agent Memory · 隐私自检（v2）══"
echo ""

# ---------- 载入本地黑名单（可选）----------
BL=""
if [ -f "${BL_FILE}" ]; then
  BL="$(grep -vE '^[[:space:]]*(#|$)' "${BL_FILE}" 2>/dev/null | paste -sd'|' -)"
fi
if [ -n "${BL}" ]; then
  echo "黑名单来源: ${BL_FILE}（本地，未入库）"
else
  echo "黑名单来源: 无（未找到 ${BL_FILE}）"
  echo "          → 身份类检查将跳过。模板见 scripts/blacklist.local.example"
fi
echo ""

# ---------- 1. 用户身份 / 邮箱 / 用户名（依赖本地黑名单）----------
if [ -n "${BL}" ]; then
  if grep -rniE "${BL}" . "${GREP_EXCLUDES[@]}" 2>/dev/null; then
    say_bad "[身份/邮箱/用户名] 疑似命中本地黑名单"
  else
    say_ok "[身份/邮箱/用户名] 无"
  fi
else
  say_skip "[身份/邮箱/用户名] 跳过（未配置本地黑名单）"
fi

# ---------- 2. 绝对家目录路径（macOS / Linux / Windows）----------
# 模式写作 [/]Users[/][A-Za-z0-9_-]+ ：只命中真实用户名，不误伤文档里的 /Users/... 占位写法
ABS_RE='[/]Users[/][A-Za-z0-9_-]+|[/]home[/][A-Za-z0-9_-]+|[Cc]:[\\/]Users[\\/][A-Za-z0-9_-]+'
if grep -rnE "$ABS_RE" . "${GREP_EXCLUDES[@]}" 2>/dev/null; then
  say_bad "[绝对路径] 命中真实用户家目录路径（换设备即失效，且可识别身份）"
else
  say_ok "[绝对路径] 无"
fi

# ---------- 3. 凭证 / 密钥 ----------
KEY_RE='sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|BEGIN (RSA|EC|OPENSSH|PGP) PRIVATE KEY'
if grep -rnE "$KEY_RE" . "${GREP_EXCLUDES[@]}" 2>/dev/null; then
  say_bad "[凭证/密钥] 疑似命中真实密钥"
else
  say_ok "[凭证/密钥] 无"
fi

# ---------- 4. PII（手机号 / 18 位身份证）----------
PII_RE='(^|[^0-9])1[3-9][0-9]{9}([^0-9]|$)|(^|[^0-9Xx])[1-9][0-9]{5}(19|20)[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9Xx]([^0-9Xx]|$)'
if grep -rnE "$PII_RE" . "${GREP_EXCLUDES[@]}" 2>/dev/null; then
  say_bad "[PII] 疑似命中手机号 / 身份证号"
else
  say_ok "[PII] 无"
fi

# ---------- 5. 危险文件名（即使内容干净也不该入库）----------
TRACKED_BAD="$(git ls-files 2>/dev/null | grep -iE '(^|/)(\.env|\.env\..*|id_rsa.*|id_ed25519.*|credentials\.json|.*\.(pem|p12|pfx|jks|keystore|key))$')"
if [ -n "$TRACKED_BAD" ]; then
  echo "$TRACKED_BAD" | sed 's/^/      /'
  say_bad "[文件名] 仓库中存在疑似密钥/凭证文件（见上）"
else
  say_ok "[文件名] 无密钥/凭证类文件"
fi

# ---------- 6. git 提交作者是否泄漏真实身份 ----------
echo ""
echo "══ git 提交作者检查 ══"
if [ -n "${BL}" ]; then
  if git log --format='%an <%ae>' 2>/dev/null | grep -iE "${BL}"; then
    say_bad "[git 作者] 提交历史含本地黑名单中的身份"
  else
    say_ok "[git 作者] 提交历史为中性作者"
  fi
else
  say_skip "[git 作者] 跳过（未配置本地黑名单）"
fi

echo ""
if [ "$LEAK" -eq 0 ]; then
  echo "✅ 全部通过，可安全提交/推送。"
else
  echo "❌ 检测到疑似泄漏，请修正后再推送（退出码 1）。"
fi
echo ""
exit $LEAK
