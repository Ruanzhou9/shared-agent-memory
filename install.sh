#!/usr/bin/env bash
# ============================================================
# Shared Agent Memory · 一键安装脚本 (macOS / Linux)
#
# 默认行为：**自动发现本机所有 agent 的技能目录**（已知约定目录 + $HOME/*/skills、
#           $HOME/.config/*/skills、Library/Application Support/*/skills），
#           把技能装到每一个，让多个 agent 共享同一份记忆。
#
# 用法:
#   bash install.sh                     安装到所有发现的目标
#   bash install.sh --only claude,codex 只装指定 agent（逗号分隔，可用路径片段）
#   bash install.sh --target /path      只装到指定目录（自定义 harness / 项目级）
#   bash install.sh --update            已存在的目标只更新协议文件，保留 memory/ 用户记忆
#   bash install.sh --dry-run           只显示将装到哪，不做任何修改
#   bash install.sh --force             目标里已有同源变体（如 shared-agent-memory-opencode）时也照装
#   bash install.sh --yes               未发现任何技能目录时，仍装入 ~/skills（默认拒绝）
#   bash install.sh --link-memory <库>  把每个目标的 memory/ 统一软链到指定真库 → 多 agent 共享同一份
#                                       （不设此参数时，各 agent 读各自目录下的 memory/，互不可见）
# ============================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${DIR}/shared-agent-memory"
DRY=0; UPDATE=0; YES=0; FORCE=0; ONLY=""; TARGET=""; LINK_MEMORY=""

usage(){ cat <<'EOF'
用法:
  bash install.sh                     安装到所有发现的目标
  bash install.sh --only claude,codex 只装指定 agent（逗号分隔，可用路径片段）
  bash install.sh --target /path      只装到指定目录（自定义 harness / 项目级）
  bash install.sh --update            已存在的目标只更新协议文件，保留 memory/ 用户记忆
  bash install.sh --link-memory <库>  把每个目标的 memory/ 改成软链 → 指定真库（多 agent 共享同一份）
  bash install.sh --dry-run           只显示将装到哪，不做任何修改
  bash install.sh --force             目标里已有同源变体时也照装
  bash install.sh --yes               未发现任何技能目录时，仍装入 ~/skills（默认拒绝）

说明: 不加 --link-memory 时，每个 agent 读「自己 SKILL.md 所在目录下」的 memory/，
      多 agent 之间**互不可见**；加上之后全部指向同一份库，实时共享。
      推荐: bash install.sh --update --link-memory "<你的真库路径>"
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --update)  UPDATE=1; shift ;;
    --force)   FORCE=1; shift ;;
    --yes|-y)  YES=1; shift ;;
    --only)
      [ $# -ge 2 ] || { echo "✗ --only 需要一个参数，如 --only claude,codex"; exit 2; }
      ONLY="$2"; shift 2 ;;
    --target)
      [ $# -ge 2 ] || { echo "✗ --target 需要一个路径参数"; exit 2; }
      TARGET="$2"; shift 2 ;;
    --link-memory)
      [ $# -ge 2 ] || { echo "✗ --link-memory 需要一个真库路径参数"; exit 2; }
      LINK_MEMORY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "✗ 未知参数: $1（用 --help 查看用法）"; exit 2 ;;
  esac
done

if [ ! -f "${SRC}/SKILL.md" ]; then
  echo "✗ 未找到 ${SRC}/SKILL.md，请在仓库根目录运行本脚本。"; exit 1
fi

# ---- --link-memory 参数校验（必须在动手前拦住明显的错路径）----
if [ -n "${LINK_MEMORY}" ]; then
  case "${LINK_MEMORY}" in "~"*) LINK_MEMORY="${HOME}${LINK_MEMORY#\~}" ;; esac
  LINK_MEMORY="${LINK_MEMORY%/}"
  if [ ! -d "${LINK_MEMORY}" ]; then
    echo "✗ --link-memory 指向的目录不存在: ${LINK_MEMORY}"; exit 1
  fi
  if [ ! -f "${LINK_MEMORY}/persona.md" ]; then
    echo "✗ ${LINK_MEMORY} 里没有 persona.md —— 这看起来不是一个记忆库，拒绝链接。"
    echo "  （正确的库根目录应直接包含 persona.md / atoms/ / scenes/ / chat-log/）"
    exit 1
  fi
fi

SKILL_NAME="shared-agent-memory"

# ---- 已知 agent 的技能父目录表（名称|首选|次选；次选存在即视为已安装）----
AGENT_SPECS=(
  "claude|${HOME}/.claude/skills|${HOME}/.claude"
  "codex|${HOME}/.codex/skills|${HOME}/.codex"
  "hermes|${HOME}/.hermes/skills|${HOME}/.hermes"
  "openclaw|${HOME}/.openclaw/skills|${HOME}/.openclaw"
  "opencode|${HOME}/.config/opencode/skills|${HOME}/.config/opencode"
  "workbuddy|${HOME}/.workbuddy/skills|${HOME}/.workbuddy"
  "copilot|${HOME}/.copilot/skills|${HOME}/.copilot"
  "dsh|${HOME}/.dsh/skills|${HOME}/.dsh"
  "agents|${HOME}/.agents/skills|${HOME}/.agents"
)

PARENTS=(); NAMES=()
add_parent(){ # $1=parent dir  $2=name —— 去重后追加
  local p="$1" n="$2" x
  for x in ${PARENTS[@]+"${PARENTS[@]}"}; do [ "$x" = "$p" ] && return; done
  PARENTS+=("$p"); NAMES+=("$n")
}

only_match(){ # $1=name $2=parent —— --only 支持按名称或路径片段过滤
  [ -z "${ONLY}" ] && return 0
  case ",${ONLY}," in *",$1,"*) return 0 ;; esac
  local IFS=',' t
  for t in ${ONLY}; do case "$2" in *"$t"*) return 0 ;; esac; done
  return 1
}

if [ -n "${TARGET}" ]; then
  add_parent "${TARGET}" "custom"
else
  # 1) 已知约定目录
  #    exist-only：该 agent 是否真读这个目录尚未验证（如 DSH），只在目录已存在时才安装，
  #                不因为父目录存在就凭空创建，避免留下"装了但没人读"的空目录
  for spec in "${AGENT_SPECS[@]}"; do
    name="${spec%%|*}"; rest="${spec#*|}"; p1="${rest%%|*}"; p2="${rest#*|}"
    mode="create"
    case "${name}" in dsh|agents) mode="exist-only" ;; esac
    only_match "${name}" "${p1}" || continue
    if   [ -d "${p1}" ]; then add_parent "${p1}" "${name}"
    elif [ "${mode}" = "create" ] && [ -d "${p2}" ]; then add_parent "${p1}" "${name}"
    elif [ "${mode}" = "exist-only" ] && [ -d "${p2}" ]; then
      echo "  ⓘ  [${name}] 未发现 ${p1}（该 agent 是否读取此目录未经验证）→ 不创建，跳过"
    fi
  done
  # 2) 自动发现其它 skills 目录（覆盖 WorkBuddy / Copilot / mimocode / clawd 等）
  #    注意：cand 本身就是「技能父目录」（agent 从它下面读 <name>/SKILL.md）
  #    隐藏目录要单独用 .*/skills 匹配（$HOME/*/skills 不含点开头目录）
  shopt -s nullglob
  for cand in "${HOME}"/*/skills "${HOME}"/.*/skills "${HOME}"/.config/*/skills \
              "${HOME}/Library/Application Support"/*/skills; do
    [ -d "${cand}" ] || continue
    case "${cand}" in
      */.Trash/*|*/.cache/*|*/.npm/*|*/.local/*|*/.git/*|*/.vscode/*|*/.Spotlight-V100/*) continue ;;
    esac
    name="$(basename "$(dirname "${cand}")")"; name="${name#.}"
    only_match "${name}" "${cand}" || continue
    add_parent "${cand}" "${name}"
  done
  shopt -u nullglob
fi

if [ "${#PARENTS[@]}" -eq 0 ]; then
  echo "⚠️  未发现任何 agent 技能目录。"
  echo "    已探测的已知路径："
  for spec in "${AGENT_SPECS[@]}"; do
    name="${spec%%|*}"; rest="${spec#*|}"; echo "      ${name}  →  ${rest%%|*}"
  done
  echo "    若你的 harness 用别的目录，请用:  bash install.sh --target <技能父目录>"
  if [ "${YES}" -ne 1 ]; then
    echo "    （重跑时加 --yes 可仍装入 ${HOME}/skills，但你的 agent 未必会读取该目录）"
    exit 1
  fi
  echo "    --yes 已指定 → 装入 ${HOME}/skills（请自行确认 agent 会读取此处）"
  add_parent "${HOME}/skills" "fallback"
fi

echo "源目录 : ${SRC}"
echo "目标数 : ${#PARENTS[@]}（${NAMES[*]}）"
echo ""

STAMP="$(date +%Y%m%d-%H%M%S)"
OK=0; SKIP=0; FILL=0; WARN=0
INSTALLED_PARENTS=()

for i in "${!PARENTS[@]}"; do
  parent="${PARENTS[$i]}"; name="${NAMES[$i]}"
  dest="${parent}/${SKILL_NAME}"

  # 同源变体检查：该技能目录下已有别的 shared-agent-memory* 变体 → 两条协议会重复加载
  variants=""
  shopt -s nullglob
  for vdir in "${parent}/${SKILL_NAME}"*; do
    [ -d "${vdir}" ] || continue
    [ "${vdir}" = "${dest}" ] && continue
    variants="${variants}$(basename "${vdir}") "
  done
  shopt -u nullglob
  if [ -n "${variants}" ] && [ "${FORCE}" -ne 1 ]; then
    echo "  ⚠️  [${name}] 该目录已有同源变体: ${variants}"
    echo "      → 跳过安装（两个变体会让同一个 agent 重复加载记忆协议）"
    echo "      → 想照装请加 --force；想只留一个请手动处理：${parent}/"
    WARN=$((WARN+1)); SKIP=$((SKIP+1)); continue
  fi

  # 软链保护：目标是指向别处（如你的私有 vault / 记忆库）的符号链接 → 永不写入，
  # 否则 --update 会把你正在用的真协议覆盖成仓库模板。
  if [ -L "${dest}" ]; then
    echo "  ⛔ [${name}] 该技能是软链 → $(readlink "${dest}")"
    echo "      → 跳过且不覆盖（软链指向你自己的记忆库/协议，覆盖会破坏线上数据）"
    SKIP=$((SKIP+1)); continue
  fi

  if [ "${DRY}" -eq 1 ]; then
    if   [ ! -e "${dest}" ];          then echo "  [dry-run] [${name}] → 新增 ${dest}"
    elif [ ! -f "${dest}/SKILL.md" ]; then echo "  [dry-run] [${name}] → 补装（目标已存在但缺 SKILL.md）${dest}"
    elif [ "${UPDATE}" -eq 1 ];       then echo "  [dry-run] [${name}] → 更新协议（保留 memory/）${dest}"
    else                                   echo "  [dry-run] [${name}] → 已存在，将跳过 ${dest}"; fi
    if [ -n "${LINK_MEMORY}" ]; then echo "             ↳ 并把 memory/ 链到 ${LINK_MEMORY}"; fi
    continue
  fi

  if [ ! -d "${parent}" ]; then
    mkdir -p "${parent}" || { echo "  ✗ [${name}] 无法创建 ${parent}"; continue; }
  fi

  if [ -f "${dest}/SKILL.md" ]; then
    if [ "${UPDATE}" -eq 1 ]; then
      mkdir -p "${dest}/.backups" "${dest}/memory/inbox"
      cp "${dest}/SKILL.md" "${dest}/.backups/SKILL.md.${STAMP}" 2>/dev/null
      cp "${SRC}/SKILL.md" "${dest}/SKILL.md" \
        && echo "  ✓ [${name}] 已更新协议（保留 memory/；旧版备份在 ${dest}/.backups/）"
      OK=$((OK+1)); INSTALLED_PARENTS+=("${parent}")
    else
      echo "  – [${name}] 已存在，跳过：${dest}"
      echo "      想只更新协议、保留你的 memory/ → 重跑加 --update"
      SKIP=$((SKIP+1))
    fi
  elif [ -e "${dest}" ]; then
    cp -R "${SRC}/." "${dest}/" && echo "  ✓ [${name}] 目标存在但缺 SKILL.md → 已补装到 ${dest}"
    FILL=$((FILL+1)); OK=$((OK+1)); INSTALLED_PARENTS+=("${parent}")
  else
    cp -R "${SRC}" "${dest}" && echo "  ✓ [${name}] 已安装到 ${dest}"
    OK=$((OK+1)); INSTALLED_PARENTS+=("${parent}")
  fi
done

if [ "${DRY}" -eq 1 ]; then echo ""; echo "[dry-run] 结束，未做任何修改。"; exit 0; fi

# ---- --link-memory：把各目标的 memory/ 统一软链到真库（多 agent 共享同一份）----
LINKED=0; LSKIP=0
if [ -n "${LINK_MEMORY}" ]; then
  echo ""
  echo "── 统一 MemoryRoot（--link-memory）──"
  for p in ${INSTALLED_PARENTS[@]+"${INSTALLED_PARENTS[@]}"}; do
    dest="${p}/${SKILL_NAME}"; m="${dest}/memory"
    label="$(basename "${p}")"
    if [ -L "${m}" ]; then
      cur="$(readlink "${m}")"
      if [ "${cur}" = "${LINK_MEMORY}" ]; then
        echo "  – [${label}] memory 已指向该库，无需改动"
      else
        echo "  ⚠️  [${label}] memory 已是软链 → ${cur}"
        echo "      → 不覆盖（可能与你的另一份库绑定）；确实要改请先手动删除该软链"
      fi
      LSKIP=$((LSKIP+1)); continue
    fi
    if [ -d "${m}" ]; then
      mkdir -p "${dest}/.backups"
      mv "${m}" "${dest}/.backups/memory-template-${STAMP}" 2>/dev/null \
        && echo "  ↳ [${label}] 原 memory/ 模板已移至 ${dest}/.backups/memory-template-${STAMP}"
    fi
    if ln -s "${LINK_MEMORY}" "${m}"; then
      echo "  ✓ [${label}] memory → ${LINK_MEMORY}"
      LINKED=$((LINKED+1))
    else
      echo "  ✗ [${label}] 创建软链失败: ${m}"
    fi
  done
  echo "  统一完成：${LINKED} 处新建链接，${LSKIP} 处跳过。"
fi

echo ""
echo "── 记忆库根目录（MemoryRoot）解析结果 ──"
if [ -n "${LINK_MEMORY}" ]; then
  echo "  --link-memory 已生效 → 各 agent 的 memory/ 统一指向："
  echo "    ${LINK_MEMORY}"
  echo "  （多个 agent 共享同一份记忆，任何一方的写入实时互通）"
elif [ -n "${SHARED_AGENT_MEMORY_ROOT:-}" ]; then
  echo "  环境变量已设置 → ${SHARED_AGENT_MEMORY_ROOT}"
  echo "  （多个 agent / 多台设备都将读写这同一份记忆库）"
else
  echo "  未设置 SHARED_AGENT_MEMORY_ROOT → 各 agent 读「自己 SKILL.md 所在目录下」的 memory/"
  echo "  本次实际写入 ${#INSTALLED_PARENTS[@]} 处："
  for p in ${INSTALLED_PARENTS[@]+"${INSTALLED_PARENTS[@]}"}; do echo "    ${p}/${SKILL_NAME}/memory"; done
  if [ "${#INSTALLED_PARENTS[@]}" -gt 1 ]; then
    echo "  ⚠️  你装了多个 agent 但各自读各自的库 → 记忆不互通！"
    echo "     想让它们共享同一份，二选一："
    echo "       a) 重跑本脚本并加 --link-memory \"<你的真库路径>\"   ← 推荐，无需重启 agent"
    echo "       b) 导出 SHARED_AGENT_MEMORY_ROOT=<你的库路径> 后再启动 agent"
  fi
fi

echo ""
echo "完成（安装/更新 ${OK} 处，其中补装 ${FILL} 处；跳过 ${SKIP} 处，含同源变体告警 ${WARN} 处）。下一步："
echo "  1) 编辑任一 memory/persona.md 与 memory/atoms/，填你自己的偏好与事实"
echo "  2) 示例在 memory/atoms/_examples/（priority=1，不会被注入，可整目录删除）"
echo "  3) 体检：bash scripts/doctor.sh    兼容性核对：bash scripts/compat-check.sh"
echo "  4) 推送前隐私自检：bash scripts/pre-push-check.sh"
echo "  5) 各 agent 新开一个会话，问它「是否加载了 shared-agent-memory」；"
echo "     若未出现：确认 SKILL.md 首行为 '---'、文件名正确，并重启 agent。"
