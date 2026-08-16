#!/usr/bin/env bash
# ============================================================
# Shared Agent Memory · 一键安装脚本
# 探测当前环境可用的 agent 类型，把 shared-agent-memory 拷到正确的技能根目录。
#
# 用法:   bash install.sh               自动探测并安装
#         bash install.sh --target /path 指定安装到指定目录
#         bash install.sh --dry-run      只显示将装到哪，不执行
# ============================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/shared-agent-memory"
DRY=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --target)  TARGET="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ ! -f "$SRC/SKILL.md" ]; then
  echo "✗ 未找到 $SRC/SKILL.md，请在仓库根目录运行本脚本。"; exit 1
fi

# ---- 探测目标目录 ----
detect_dest() {
  [ -n "$TARGET" ] && { echo "$TARGET"; return; }
  # 按常见 agent 的约定目录探测（命中的第一个）
  [ -d "$HOME/.claude/skills" ]        && { echo "$HOME/.claude/skills";        return; }
  [ -d "$HOME/.claude" ]               && { echo "$HOME/.claude/skills";        return; }
  [ -d "$HOME/.hermes/skills" ]        && { echo "$HOME/.hermes/skills";        return; }
  [ -d "$HOME/.openclaw/skills" ]      && { echo "$HOME/.openclaw/skills";      return; }
  [ -d "$HOME/.codex/skills" ]         && { echo "$HOME/.codex/skills";         return; }
  [ -d "$HOME/.dsh/skills" ]           && { echo "$HOME/.dsh/skills";           return; }
  # 都没有：装到用户目录下的 skills
  echo "$HOME/skills"
}

DEST_PARENT="$(detect_dest)"
DEST="$DEST_PARENT/shared-agent-memory"

echo "源目录  : $SRC"
echo "目标位置: $DEST"
if [ "$DRY" -eq 1 ]; then echo "[dry-run] 结束，未安装。"; exit 0; fi

mkdir -p "$DEST_PARENT" || { echo "✗ 无法创建目标目录: $DEST_PARENT"; exit 1; }
if [ -e "$DEST" ]; then
  echo "⚠️ 目标已存在，未覆盖: $DEST"
else
  cp -R "$SRC" "$DEST" && echo "✓ 已安装到 $DEST"
fi

echo ""
echo "完成。请新开一个 agent 会话，询问它是否加载了 shared-agent-memory。"
echo "若未出现：确认 $DEST/SKILL.md 首行为 '---'，并重启 agent。"
