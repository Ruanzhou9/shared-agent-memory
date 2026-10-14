#!/usr/bin/env bash
# ============================================================
# 记忆库体检 (doctor)：把协议里的「硬要求」变成可校验的检查。
#
# 用法:
#   bash scripts/doctor.sh                 # 检查仓库内模板库
#   bash scripts/doctor.sh <memory目录>     # 检查指定库（如你的私有库）
#   bash scripts/doctor.sh --strict        # 警告也视为失败（适合 CI）
#
# 退出码: 0=通过(可含警告)  1=发现错误  2=用法/路径错误
#
# 检查项:
#   A 容量阈值   persona 建议 ≤3KB（软阈值，仅提醒不阻断）/ atoms ≤100 条 且 ≤256KB
#   B schema     frontmatter 是否闭合、必填字段、type/status 枚举、priority/confidence 取值
#   C 双轴一致   priority 与 confidence/status 是否失衡
#   D 新鲜度     priority>=6 是否带 verified、是否超过 180 天未复核
#   E 指针规范   chat-log 是否含机器绝对路径
#   F 去重       首句完全相同的原子条目
#   G inbox     各 agent 候选积压量（>10 条提示晋升）
#   H 版本      SKILL.md 的 version 字段
#   I 淘汰候选   priority<=4 且超 180 天未复核（评分卡淘汰机制，v1.2）
# ============================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
STRICT=0
MEM=""

for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) MEM="$a" ;;
  esac
done

# MemoryRoot 解析：显式参数 > 环境变量 > 本仓库模板库
if [ -z "${MEM}" ]; then
  if [ -n "${SHARED_AGENT_MEMORY_ROOT:-}" ]; then
    if [ -f "${SHARED_AGENT_MEMORY_ROOT}/persona.md" ]; then MEM="${SHARED_AGENT_MEMORY_ROOT}"
    else MEM="${SHARED_AGENT_MEMORY_ROOT}/memory"; fi
  else
    MEM="${HERE}/shared-agent-memory/memory"
  fi
fi
MEM="${MEM%/}"

if [ ! -d "${MEM}" ]; then
  echo "✗ 记忆库目录不存在: ${MEM}" >&2
  echo "  用法: bash scripts/doctor.sh [memory目录]" >&2
  exit 2
fi

# 容量阈值：可用环境变量覆盖，无需改脚本
#   SAM_PERSONA_SOFT / SAM_ATOMS_MAX_COUNT / SAM_ATOMS_MAX_BYTES
PERSONA_SOFT="${SAM_PERSONA_SOFT:-3072}"           # 建议基线 3 KB —— 软阈值，超出仅提醒、不阻断
ATOMS_MAX_COUNT="${SAM_ATOMS_MAX_COUNT:-100}"      # 100 条（v1.3 由 50 放宽）
ATOMS_MAX_BYTES="${SAM_ATOMS_MAX_BYTES:-262144}"   # 256 KB（v1.3 由 100 KB 放宽）
ATOMS_WARN_COUNT=$((ATOMS_MAX_COUNT * 8 / 10))
ATOMS_WARN_BYTES=$((ATOMS_MAX_BYTES * 8 / 10))
STALE_DAYS=180
INBOX_WARN=10

ERR=0; WARN=0
err(){  echo "    ✗ $1"; ERR=$((ERR+1)); }
warn(){ echo "    ⚠️  $1"; WARN=$((WARN+1)); }
ok(){   echo "  ✓ $1"; }
info(){ echo "    · $1"; }

echo "══ 共享 Agent Memory · 记忆库体检 ══"
echo "库位置: ${MEM}"
echo ""

# ---------- 工具函数 ----------
fm_closed(){ # 输出 closed / unclosed / noopen
  awk '
    NR==1 { if ($0 !~ /^---[[:space:]]*$/) { print "noopen"; bad=1; exit } }
    { if ($0 ~ /^---[[:space:]]*$/) n++ }
    END { if (!bad) { if (n>=2) print "closed"; else print "unclosed" } }
  ' "$1"
}
fm_get(){ # $1=file $2=key  → 值（去掉两侧空白）
  awk -v k="$2" '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR>1 && $0 ~ /^---[[:space:]]*$/ { exit }
    NR>1 { if (index($0, k ":") == 1) { v=$0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v); print v; exit } }
  ' "$1"
}
body_first_line(){
  awk '
    NR==1 { if ($0 ~ /^---[[:space:]]*$/) { n=1; next } }
    { if ($0 ~ /^---[[:space:]]*$/) { n++; next } }
    { if ((n>=2 || n==0) && $0 !~ /^[[:space:]]*$/) { print; exit } }
  ' "$1"
}
body_nonempty_count(){
  awk '
    NR==1 { if ($0 ~ /^---[[:space:]]*$/) { n=1; next } }
    { if ($0 ~ /^---[[:space:]]*$/) { n++; next } }
    { if ((n>=2 || n==0) && $0 !~ /^[[:space:]]*$/) c++ }
    END { print c+0 }
  ' "$1"
}
ABS_RE='[/]Users[/][A-Za-z0-9_-]+|[/]home[/][A-Za-z0-9_-]+|[Cc]:[\\/]Users[\\/][A-Za-z0-9_-]+'

# ---------- A. 容量阈值 ----------
echo "[A] 容量阈值"
if [ -f "${MEM}/persona.md" ]; then
  PSIZE=$(wc -c < "${MEM}/persona.md" | tr -d ' ')
  if [ "${PSIZE}" -gt "${PERSONA_SOFT}" ]; then
    warn "persona.md 超出建议基线: ${PSIZE} B > ${PERSONA_SOFT} B（软阈值，不阻断；建议做一次去重、把细节下沉为原子记忆）"
  elif [ "${PSIZE}" -gt $((PERSONA_SOFT * 9 / 10)) ]; then
    warn "persona.md 接近建议基线: ${PSIZE} B / ${PERSONA_SOFT} B（余量 $((PERSONA_SOFT - PSIZE)) B）"
  else
    ok "persona.md ${PSIZE} B / 建议 ${PERSONA_SOFT} B"
  fi
else
  err "缺少 persona.md（记忆库根目录无 L3 画像）"
fi

ATOM_FILES=""
while IFS= read -r f; do
  [ -n "$f" ] && ATOM_FILES="${ATOM_FILES}${f}\n"
done < <(find "${MEM}/atoms" -maxdepth 1 -type f -name '*.md' ! -name '_*' 2>/dev/null | sort)
ATOM_FILES="$(printf '%b' "${ATOM_FILES}")"
TEMPLATE_N=$(find "${MEM}/atoms" -maxdepth 1 -type f -name '_*' 2>/dev/null | wc -l | tr -d ' ')
ACOUNT=0; ABYTES=0
if [ -n "${ATOM_FILES}" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    ACOUNT=$((ACOUNT+1))
    ABYTES=$((ABYTES + $(wc -c < "$f" | tr -d ' ')))
  done <<< "${ATOM_FILES}"
fi
[ "${TEMPLATE_N}" -gt 0 ] && info "已跳过 ${TEMPLATE_N} 个模板/示例文件（_ 前缀，不属记忆，不参与校验）"
if [ "${ACOUNT}" -gt "${ATOMS_MAX_COUNT}" ]; then
  err "atoms 条数超限: ${ACOUNT} > ${ATOMS_MAX_COUNT}（应归并：合并同义、降级过期、细节下沉；确需更多可用 SAM_ATOMS_MAX_COUNT 上调）"
elif [ "${ACOUNT}" -eq 0 ]; then
  info "atoms 为空（模板库正常；真实库为空说明尚未沉淀记忆）"
elif [ "${ACOUNT}" -gt "${ATOMS_WARN_COUNT}" ]; then
  warn "atoms 条数接近上限: ${ACOUNT} / ${ATOMS_MAX_COUNT}（建议归并同义项）"
else
  ok "atoms ${ACOUNT} 条 / 上限 ${ATOMS_MAX_COUNT}"
fi
if [ "${ABYTES}" -gt "${ATOMS_MAX_BYTES}" ]; then
  err "atoms 总体积超限: ${ABYTES} B > ${ATOMS_MAX_BYTES} B"
elif [ "${ABYTES}" -gt "${ATOMS_WARN_BYTES}" ]; then
  warn "atoms 总量接近上限: ${ABYTES} B / ${ATOMS_MAX_BYTES} B"
elif [ "${ABYTES}" -gt 0 ]; then
  ok "atoms 总量 ${ABYTES} B / ${ATOMS_MAX_BYTES} B"
fi
echo ""

# ---------- B/C/D. 逐条校验 ----------
echo "[B] schema · [C] 双轴一致 · [D] 新鲜度"
CUTOFF=""
if date -v-"${STALE_DAYS}"d +%Y-%m-%d >/dev/null 2>&1; then
  CUTOFF="$(date -v-"${STALE_DAYS}"d +%Y-%m-%d)"
elif date -d "-${STALE_DAYS} days" +%Y-%m-%d >/dev/null 2>&1; then
  CUTOFF="$(date -d "-${STALE_DAYS} days" +%Y-%m-%d)"
fi

DUP_TMP="$(mktemp)"; trap 'rm -f "${DUP_TMP}"' EXIT
DUP_HITS=0; STALE_HITS=0; SCHEMA_HITS=0

if [ -n "${ATOM_FILES}" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel="${f#${MEM}/}"
    status="$(fm_closed "$f")"
    if [ "$status" != "closed" ]; then
      case "$status" in
        noopen)  err "${rel}: 缺少 frontmatter（首行应为 ---）" ;;
        unclosed) err "${rel}: frontmatter 未闭合（疑似半截文件，读入会污染上下文）" ;;
      esac
      SCHEMA_HITS=$((SCHEMA_HITS+1)); continue
    fi

    typ="$(fm_get "$f" type)"
    pri="$(fm_get "$f" priority)"
    conf="$(fm_get "$f" confidence)"
    st="$(fm_get "$f" status)"
    ver="$(fm_get "$f" verified)"
    cre="$(fm_get "$f" created)"
    upd="$(fm_get "$f" updated)"

    [ -z "$typ" ]  && { err "${rel}: 缺少必填字段 type"; SCHEMA_HITS=$((SCHEMA_HITS+1)); }
    case "$typ" in
      ""|preference|fact|handling|constraint) : ;;
      *) err "${rel}: type 取值非法（${typ}），应为 preference|fact|handling|constraint"; SCHEMA_HITS=$((SCHEMA_HITS+1)) ;;
    esac
    [ -z "$cre" ] && { err "${rel}: 缺少必填字段 created"; SCHEMA_HITS=$((SCHEMA_HITS+1)); }
    [ -z "$upd" ] && { err "${rel}: 缺少必填字段 updated"; SCHEMA_HITS=$((SCHEMA_HITS+1)); }

    if [ -z "$pri" ]; then
      err "${rel}: 缺少必填字段 priority（注入门控依赖它）"; SCHEMA_HITS=$((SCHEMA_HITS+1))
    elif ! printf '%s' "$pri" | grep -qE '^([1-9]|10)$'; then
      err "${rel}: priority 非法（${pri}），应为 1-10 整数"; SCHEMA_HITS=$((SCHEMA_HITS+1))
    fi

    if [ -n "$conf" ] && ! printf '%s' "$conf" | grep -qE '^(0(\.[0-9]+)?|1(\.0+)?)$'; then
      err "${rel}: confidence 非法（${conf}），应为 0-1"; SCHEMA_HITS=$((SCHEMA_HITS+1))
    fi

    if [ -n "$st" ]; then
      case "$st" in
        candidate|active|user-accepted|superseded|archived) : ;;
        *) err "${rel}: status 不在枚举内（${st}）→ candidate|active|user-accepted|superseded|archived"; SCHEMA_HITS=$((SCHEMA_HITS+1)) ;;
      esac
    fi

    if [ -n "$ver" ] && ! printf '%s' "$ver" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      err "${rel}: verified 格式非法（${ver}），应为 YYYY-MM-DD"; SCHEMA_HITS=$((SCHEMA_HITS+1))
    fi

    if [ "$(body_nonempty_count "$f")" -eq 0 ]; then
      err "${rel}: 正文为空（frontmatter 之后没有任何声明）"; SCHEMA_HITS=$((SCHEMA_HITS+1))
    fi

    # C. 双轴一致性
    if printf '%s' "$pri" | grep -qE '^([6-9]|10)$'; then
      [ -z "$st" ] && warn "${rel}: priority=${pri} 但未标 status（高注入条目应显式声明可信状态）"
      if [ -n "$conf" ] && awk -v c="$conf" 'BEGIN{exit !(c<0.6)}'; then
        warn "${rel}: 双轴失衡 —— priority=${pri}（会主动注入）却 confidence=${conf}（低可信）"
      fi
    fi
    if [ "$st" = "user-accepted" ] && [ -n "$conf" ] && awk -v c="$conf" 'BEGIN{exit !(c<0.85)}'; then
      warn "${rel}: status=user-accepted 但 confidence=${conf} < 0.85（归属不清，需校准）"
    fi

    # D. 新鲜度
    if printf '%s' "$pri" | grep -qE '^([6-9]|10)$'; then
      if [ -z "$ver" ]; then
        warn "${rel}: priority=${pri} 缺 verified（无法判断是否已过时）"; STALE_HITS=$((STALE_HITS+1))
      elif [ -n "$CUTOFF" ] && [ "$ver" \< "$CUTOFF" ]; then
        warn "${rel}: verified=${ver} 已超过 ${STALE_DAYS} 天未复核（可能自信地记住过时的事）"; STALE_HITS=$((STALE_HITS+1))
      fi
    fi

    # F. 去重
    first="$(body_first_line "$f" | tr -d '\r')"
    if [ -n "$first" ]; then
      if grep -Fqx -- "$first" "${DUP_TMP}" 2>/dev/null; then
        warn "${rel}: 首句与已有条目完全相同（疑似重复，应合并）"; DUP_HITS=$((DUP_HITS+1))
      else
        printf '%s\n' "$first" >> "${DUP_TMP}"
      fi
    fi
  done <<< "${ATOM_FILES}"
fi

if [ "${SCHEMA_HITS}" -eq 0 ] && [ "${ACOUNT}" -gt 0 ]; then ok "atoms schema 全部合规"; fi
if [ "${SCHEMA_HITS}" -eq 0 ] && [ "${ACOUNT}" -eq 0 ]; then info "无 atoms 可校验"; fi
if [ "${STALE_HITS}" -eq 0 ] && [ "${ACOUNT}" -gt 0 ]; then ok "无缺 verified / 无超过 ${STALE_DAYS} 天未复核的高优先条目"; fi
if [ "${DUP_HITS}" -eq 0 ] && [ "${ACOUNT}" -gt 0 ]; then ok "未发现首句重复条目"; fi
[ -z "${CUTOFF}" ] && info "（本机 date 不支持相对日期，已跳过超期判断）"
echo ""

# ---------- E. chat-log 指针规范 ----------
echo "[E] chat-log 指针"
CL_BAD=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  hit="$(grep -nE "${ABS_RE}" "$f" 2>/dev/null | head -3)"
  if [ -n "${hit}" ]; then
    err "${f#${MEM}/}: 含机器绝对路径指针（换设备即失效 + 触发隐私自检）"
    echo "${hit}" | sed 's/^/        /'
    CL_BAD=$((CL_BAD+1))
  fi
done < <(find "${MEM}/chat-log" -type f -name '*.md' 2>/dev/null | sort)
[ "${CL_BAD}" -eq 0 ] && ok "chat-log 无机器绝对路径"
echo ""

# ---------- G. inbox 积压 ----------
echo "[G] inbox 候选积压"
INBOX_DIR="${MEM}/inbox"
if [ -d "${INBOX_DIR}" ]; then
  FOUND=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    n=$(find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    slug="$(basename "$d")"
    if [ "${n}" -gt 0 ]; then
      FOUND=1
      if [ "${n}" -gt "${INBOX_WARN}" ]; then
        warn "inbox/${slug} 积压 ${n} 条候选（> ${INBOX_WARN}）→ 该做一次晋升评估"
      else
        info "inbox/${slug}：${n} 条候选待晋升"
      fi
    fi
    # 多机同步时，同代号目录会撞车：提示改为 <agent>-<host>
    case "${slug}" in
      *-*) : ;;
      *) warn "inbox/${slug} 代号未含主机后缀 → 多设备同步时建议改为 <agent>-<host>（如 workbuddy-mac-m3），否则同 agent 两台机器会写同一目录、同名候选将冲突" ;;
    esac
  done < <(find "${INBOX_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  [ "${FOUND}" -eq 0 ] && ok "inbox 无待晋升候选"
else
  warn "缺少 inbox/ 目录（v1.1 的并发写隔离依赖它）"
fi
echo ""

# ---------- H. 协议版本 ----------
echo "[H] 协议版本"
SKILL="$(dirname "${MEM}")/SKILL.md"
if [ -f "${SKILL}" ]; then
  v="$(fm_get "${SKILL}" version)"
  [ -n "$v" ] && ok "SKILL.md version: ${v}" || warn "SKILL.md 未声明 version（协议演进时无法区分新旧）"
else
  info "（当前库不在技能目录内，跳过 SKILL.md 版本检查）"
fi
echo ""

# ---------- I. 淘汰候选（v1.2 评分卡淘汰机制）----------
echo "[I] 淘汰候选（priority≤4 且超 ${STALE_DAYS} 天未复核）"
EVICT=0; N_INJ=0; N_RES=0
if [ -n "${ATOM_FILES}" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    pri="$(fm_get "$f" priority)"
    st="$(fm_get "$f" status)"
    ver="$(fm_get "$f" verified)"
    rel="${f#${MEM}/}"
    case "$pri" in
      5) N_RES=$((N_RES+1)); continue ;;
      6|7|8|9|10) N_INJ=$((N_INJ+1)); continue ;;
      1|2|3|4) : ;;
      *) continue ;;
    esac
    # 已归档/被取代的条目是既往淘汰的结果，不算新候选
    if [ "$st" = "archived" ] || [ "$st" = "superseded" ]; then continue; fi
    stale=0
    if [ -z "$ver" ]; then
      stale=1
    elif [ -n "$CUTOFF" ] && [ "$ver" \< "$CUTOFF" ]; then
      stale=1
    fi
    if [ "$stale" -eq 1 ]; then
      if [ -z "$ver" ]; then
        warn "${rel}: priority=${pri} 且无 verified → 淘汰候选（按入库评分卡复核，<7 分应归档或删除，先问用户）"
      else
        warn "${rel}: priority=${pri} 且 verified=${ver} 已超 ${STALE_DAYS} 天未复核 → 淘汰候选"
      fi
      EVICT=$((EVICT+1))
    fi
  done <<< "${ATOM_FILES}"
fi
if [ "${ACOUNT}" -gt 0 ]; then
  info "注入中(priority≥6) ${N_INJ} 条 · 储备(=5) ${N_RES} 条 · 淘汰候选 ${EVICT} 条"
  [ "${EVICT}" -eq 0 ] && ok "无淘汰候选"
else
  info "无 atoms 可校验"
fi
echo ""

echo "══ 汇总 ══"
echo "  错误 ${ERR} · 警告 ${WARN}"
if [ "${ERR}" -gt 0 ]; then
  echo "  ❌ 存在错误，请修正后重跑。"
  exit 1
elif [ "${WARN}" -gt 0 ] && [ "${STRICT}" -eq 1 ]; then
  echo "  ❌ --strict 模式下警告视为失败。"
  exit 1
elif [ "${WARN}" -gt 0 ]; then
  echo "  ⚠️  仅警告，不阻塞（加 --strict 可让警告也失败）。"
  exit 0
else
  echo "  ✅ 全部通过。"
  exit 0
fi
