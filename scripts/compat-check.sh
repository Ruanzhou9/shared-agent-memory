#!/usr/bin/env bash
# ============================================================
# 跨 agent 兼容性核对 (compat-check)
#
# 回答一个问题：这份技能装到本机每个 agent 的技能目录后，**它们能不能读得出来**。
#
# 用法:
#   bash scripts/compat-check.sh          自动发现并核对所有 agent 技能目录
#   bash scripts/compat-check.sh <目录>   只核对指定技能父目录（可多次）
#   bash scripts/compat-check.sh --strict 警告也算失败
#
# 退出码: 0=全部兼容  1=存在问题  2=用法错误
#
# 核对项（每条都是各 agent 加载器实际依赖的约定）:
#   1 目录/文件就位     <dir>/shared-agent-memory/SKILL.md 是否存在
#   2 首行 `---`         技能加载器识别 frontmatter 的前提
#   3 frontmatter 闭合   未闭合会被当成正文，加载失败或读入垃圾
#   4 name 与目录同名    多数 agent 用目录名与 name 交叉校验
#   5 description 存在且 ≤1024 字符（Claude Code / Agent Skills 规范的硬限制）
#   6 version 存在       协议演进时用于判断副本新旧
#   7 编码健康          无 BOM、无 CRLF、UTF-8 合法
#   8 记忆库就位         memory/persona.md 存在，且打印 MemoryRoot 解析结果
#   9 同目录已有技能数    证明该 agent 确实从这个目录读技能（旁证）
#  10 同源变体告警       同一目录存在 shared-agent-memory* 其它变体 → 会重复加载
# ============================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_SRC="${HERE}/shared-agent-memory"
SKILL_NAME="shared-agent-memory"
STRICT=0; DIRS=()

for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DIRS+=("$a") ;;
  esac
done

if [ "${#DIRS[@]}" -eq 0 ]; then
  AGENT_SPECS=(
    "claude|${HOME}/.claude/skills"
    "codex|${HOME}/.codex/skills"
    "hermes|${HOME}/.hermes/skills"
    "openclaw|${HOME}/.openclaw/skills"
    "opencode|${HOME}/.config/opencode/skills"
    "workbuddy|${HOME}/.workbuddy/skills"
    "copilot|${HOME}/.copilot/skills"
    "agents|${HOME}/.agents/skills"
  )
  for spec in "${AGENT_SPECS[@]}"; do [ -d "${spec#*|}" ] && DIRS+=("${spec#*|}"); done
  # 自动发现其它 skills 目录（与 install.sh 的发现规则保持一致）
  shopt -s nullglob
  for cand in "${HOME}"/*/skills "${HOME}"/.*/skills "${HOME}"/.config/*/skills \
              "${HOME}/Library/Application Support"/*/skills; do
    [ -d "${cand}" ] || continue
    case "${cand}" in
      */.Trash/*|*/.cache/*|*/.npm/*|*/.local/*|*/.git/*|*/.vscode/*|*/.Spotlight-V100/*) continue ;;
    esac
    seen=0; for d in ${DIRS[@]+"${DIRS[@]}"}; do [ "$d" = "$cand" ] && seen=1; done
    [ "$seen" -eq 0 ] && DIRS+=("$cand")
  done
  shopt -u nullglob
fi
[ "${#DIRS[@]}" -eq 0 ] && { echo "✗ 未发现任何技能目录"; exit 2; }

ERR=0; WARN=0; INSTALLED=0; MISSING=0; LINKED=0
ISLINK=0
err(){
  if [ "${ISLINK}" -eq 1 ]; then
    echo "      🔗 $1（软链目标，仅提示，不计失败）"; WARN=$((WARN+1))
  else
    echo "      ✗ $1"; ERR=$((ERR+1))
  fi
}
warn(){ echo "      ⚠️  $1"; WARN=$((WARN+1)); }
ok(){   echo "      ✓ $1"; }

echo "══ 跨 agent 兼容性核对 ══"
echo "技能源: ${SKILL_SRC}"
echo ""

for d in "${DIRS[@]}"; do
  dest="${d}/${SKILL_NAME}"
  peers=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo "▸ ${d/#$HOME/~}   （该目录已有 ${peers} 个技能）"

  if [ ! -d "${dest}" ]; then
    echo "      – 未安装（本目录无 ${SKILL_NAME}/）"; MISSING=$((MISSING+1)); echo ""; continue
  fi
  INSTALLED=$((INSTALLED+1))

  # 软链安装（常见于把技能链到自己的私有记忆库）：校验目标文件，但不判失败
  ISLINK=0
  if [ -L "${dest}" ]; then
    ISLINK=1; LINKED=$((LINKED+1))
    echo "      🔗 软链 → $(readlink "${dest}")"
    echo "         （校验的是目标文件；若目标自带 MemoryRoot 指向别处，则 persona 不在技能目录内属正常）"
  fi

  if [ ! -f "${dest}/SKILL.md" ]; then
    err "目录存在但缺 SKILL.md → agent 读不到（历史残留的空壳目录，确认无用后可删除）"; echo ""; continue
  fi

  FM="${dest}/SKILL.md"
  [ "$(head -1 "$FM")" = "---" ] && ok "首行 ---（frontmatter 可识别）" || err "首行不是 --- → 多数加载器会忽略整个技能"

  closed=$(awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ {print "noopen"; bad=1; exit}
                { if ($0 ~ /^---[[:space:]]*$/) n++ }
                END { if (!bad) print (n>=2 ? "closed" : "unclosed") }' "$FM")
  case "$closed" in
    closed)   ok "frontmatter 已闭合" ;;
    unclosed) err "frontmatter 未闭合 → 正文会被读成元数据" ;;
    noopen)   : ;;
  esac

  name=$(awk 'NR==1&&$0!~/^---/{exit} NR>1&&/^---/{exit} NR>1&&index($0,"name:")==1{v=$0;sub(/^[^:]*:[[:space:]]*/,"",v);print v;exit}' "$FM")
  base=$(basename "${dest}")
  if [ -z "$name" ]; then err "缺 name 字段"
  elif [ "$name" != "$base" ]; then warn "name=${name} 与目录名 ${base} 不一致（部分 agent 会交叉校验）"
  else ok "name=${name} 与目录名一致"; fi

  desc=$(awk 'NR==1&&$0!~/^---/{exit} NR>1&&/^---/{exit} NR>1&&index($0,"description:")==1{v=$0;sub(/^[^:]*:[[:space:]]*/,"",v);print v;exit}' "$FM")
  if [ -z "$desc" ]; then err "缺 description 字段（agent 靠它决定何时加载）"
  else
    dlen=$(printf '%s' "$desc" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    if [ "$dlen" -gt 1024 ]; then err "description ${dlen} 字符 > 1024（超出 Claude Code / Agent Skills 规范上限，会被截断或拒载）"
    else ok "description ${dlen} 字符（≤1024）"; fi
  fi

  ver=$(awk 'NR==1&&$0!~/^---/{exit} NR>1&&/^---/{exit} NR>1&&index($0,"version:")==1{v=$0;sub(/^[^:]*:[[:space:]]*/,"",v);print v;exit}' "$FM")
  [ -n "$ver" ] && ok "version=${ver}" || warn "未声明 version（无法判断副本新旧）"

  if head -c3 "$FM" | grep -q $'\xef\xbb\xbf'; then err "文件带 BOM → 部分加载器读不出首行 ---"; else ok "无 BOM"; fi
  grep -qU $'\r' "$FM" && err "存在 CRLF 换行 → frontmatter 解析可能失败" || ok "换行符 LF"
  # UTF-8 合法性：优先 python3（可靠），退化用 file(1)。
  # 注意：不能只用 iconv —— macOS 自带 iconv 在同编码转换时会报 "Inappropriate ioctl"，属误报。
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import sys;open(sys.argv[1],encoding="utf-8").read()' "$FM" 2>/dev/null; then
      ok "UTF-8 编码合法"
    else
      err "非合法 UTF-8（agent 读取会乱码/报错）"
    fi
  else
    enc="$(file -Ib "$FM" 2>/dev/null || file -b --mime-encoding "$FM" 2>/dev/null)"
    case "$enc" in
      *utf-8*|*us-ascii*) ok "UTF-8 编码合法（file: ${enc}）" ;;
      *) err "编码疑似非 UTF-8：${enc}" ;;
    esac
  fi

  if [ -f "${dest}/memory/persona.md" ]; then
    if [ -n "${SHARED_AGENT_MEMORY_ROOT:-}" ]; then
      ok "memory/persona.md 就位；MemoryRoot 解析 → ${SHARED_AGENT_MEMORY_ROOT}（环境变量）"
    else
      ok "memory/persona.md 就位；MemoryRoot 解析 → ${dest}/memory"
    fi
  elif [ "${ISLINK}" -eq 1 ]; then
    warn "技能目录内无 memory/persona.md —— 软链目标多半自带 MemoryRoot（指向你私有的记忆库），属正常"
  else
    err "缺 memory/persona.md → 协议找不到记忆库"
  fi

  shopt -s nullglob
  var=""
  for vdir in "${d}/${SKILL_NAME}"*; do
    [ -d "$vdir" ] || continue; [ "$vdir" = "$dest" ] && continue
    var="${var}$(basename "$vdir") "
  done
  shopt -u nullglob
  [ -n "$var" ] && warn "同目录存在同源变体：${var}→ 该 agent 会**重复加载**两份记忆协议，建议只留一个" \
                || ok "无同源变体"

  if [ "${#DIRS[@]}" -le 2 ]; then :; fi

  echo ""
done

echo "══ 汇总 ══"
echo "  已安装 ${INSTALLED} 个 agent 目录 · 未安装 ${MISSING} 个 · 错误 ${ERR} · 警告 ${WARN}"
if [ "${INSTALLED}" -eq 0 ]; then
  echo "  ❌ 没有任何 agent 目录装着本技能。先跑 bash install.sh"; exit 1
fi
if [ "${ERR}" -gt 0 ]; then echo "  ❌ 存在兼容性问题，见上。"; exit 1; fi
if [ "${WARN}" -gt 0 ] && [ "${STRICT}" -eq 1 ]; then echo "  ❌ --strict：警告视为失败。"; exit 1; fi
[ "${WARN}" -gt 0 ] && echo "  ⚠️  有警告但不阻塞（加 --strict 可让警告也失败）。" || echo "  ✅ 全部兼容。"
exit 0
