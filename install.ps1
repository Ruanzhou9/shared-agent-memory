<#
    ============================================================
    Shared Agent Memory · 一键安装脚本 (PowerShell / Windows)
    与 install.sh 语义对齐：自动发现本机所有 agent 的技能目录
    （已知约定目录 + 用户目录与 .config 下的 */skills），把技能装到每一个。

    用法:
        powershell -ExecutionPolicy Bypass -File install.ps1
        .\install.ps1 -DryRun
        .\install.ps1 -Only claude,codex
        .\install.ps1 -Target "C:\path\to\skills"
        .\install.ps1 -Update          # 已存在的目标只更新协议，保留 memory/ 用户记忆
        .\install.ps1 -Force           # 目标里已有同源变体时也照装
        .\install.ps1 -Yes             # 未发现技能目录时仍装入 ~\skills（默认拒绝）
        .\install.ps1 -LinkMemory "C:\path\to\memory"
                                       # 把每个目标的 memory\ 变成 Junction → 指定真库
                                       # （多 agent 共享同一份；不设时各读各自目录，互不可见）
    ============================================================
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Update,
    [switch]$Force,
    [switch]$Yes,
    [string]$Only = "",
    [string]$Target = "",
    [string]$LinkMemory = ""
)

$ErrorActionPreference = 'Stop'
$SRC = Join-Path $PSScriptRoot 'shared-agent-memory'
$SKILL_NAME = 'shared-agent-memory'
$DRY = [bool]$DryRun
$HOME_DIR = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if (-not $HOME_DIR) {
    Write-Host "✗ 无法确定用户主目录（USERPROFILE / HOME 均为空）。" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $SRC 'SKILL.md'))) {
    Write-Host "✗ 未找到 $SRC\SKILL.md，请在仓库根目录运行本脚本。" -ForegroundColor Red
    exit 1
}

# ---- -LinkMemory 参数校验（动手前先拦住明显的错路径）----
if ($LinkMemory) {
    $LinkMemory = $LinkMemory.TrimEnd('\', '/')
    if (-not (Test-Path $LinkMemory)) {
        Write-Host "✗ -LinkMemory 指向的目录不存在: $LinkMemory" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path (Join-Path $LinkMemory 'persona.md'))) {
        Write-Host "✗ $LinkMemory 里没有 persona.md —— 这看起来不是一个记忆库，拒绝链接。" -ForegroundColor Red
        Write-Host "  （正确的库根目录应直接包含 persona.md / atoms\ / scenes\ / chat-log\）"
        exit 1
    }
    $LinkMemory = (Get-Item $LinkMemory).FullName
}

# ---- 已知 agent 的技能父目录表（与 install.sh / README 手动方式表同步）----
$AGENT_SPECS = @(
    @{ name = 'claude';    dir = '.claude\skills';          parent = '.claude' },
    @{ name = 'codex';     dir = '.codex\skills';           parent = '.codex' },
    @{ name = 'hermes';    dir = '.hermes\skills';          parent = '.hermes' },
    @{ name = 'openclaw';  dir = '.openclaw\skills';        parent = '.openclaw' },
    @{ name = 'opencode';  dir = '.config\opencode\skills'; parent = '.config\opencode' },
    @{ name = 'workbuddy'; dir = '.workbuddy\skills';       parent = '.workbuddy' },
    @{ name = 'copilot';   dir = '.copilot\skills';         parent = '.copilot' },
    @{ name = 'dsh';       dir = '.dsh\skills';             parent = '.dsh' },
    @{ name = 'agents';    dir = '.agents\skills';          parent = '.agents' }
)

$onlyList = @()
if ($Only) { $onlyList = $Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }

$PARENTS = New-Object System.Collections.ArrayList
$NAMES   = New-Object System.Collections.ArrayList

function Add-Target([string]$parent, [string]$name) {
    foreach ($p in $PARENTS) { if ($p -eq $parent) { return } }
    [void]$PARENTS.Add($parent)
    [void]$NAMES.Add($name)
    return
}
function Test-Only([string]$name, [string]$parent) {
    if ($onlyList.Count -eq 0) { return $true }
    if ($onlyList -contains $name) { return $true }
    foreach ($t in $onlyList) { if ($parent -like "*$t*") { return $true } }
    return $false
}

if ($Target) {
    Add-Target $Target 'custom'
} else {
    foreach ($spec in $AGENT_SPECS) {
        if (-not (Test-Only $spec.name (Join-Path $HOME_DIR $spec.dir))) { continue }
        $skillsPath = Join-Path $HOME_DIR $spec.dir
        $parentPath = Join-Path $HOME_DIR $spec.parent
        if (Test-Path $skillsPath)     { Add-Target $skillsPath $spec.name }
        elseif (Test-Path $parentPath) { Add-Target $skillsPath $spec.name }
    }
    # 自动发现其它 skills 目录（覆盖 Copilot / mimocode / clawd 等；隐藏目录单独用 .*\skills 匹配）
    $globs = @(
        (Join-Path $HOME_DIR '*\skills'),
        (Join-Path $HOME_DIR '.*\skills'),
        (Join-Path $HOME_DIR '.config\*\skills'),
        (Join-Path $HOME_DIR 'AppData\Roaming\*\skills')
    )
    foreach ($g in $globs) {
        Get-Item -Path $g -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
            $cand = $_.FullName
            if ($cand -match '\\(\.Trash|\.cache|\.npm|\.local|\.git|\.vscode)\\\skills$') { return }
            $name = Split-Path (Split-Path $cand -Parent) -Leaf
            $name = $name.TrimStart('.')
            if (-not (Test-Only $name $cand)) { return }
            Add-Target $cand $name
        }
    }
}

if ($PARENTS.Count -eq 0) {
    Write-Host "⚠️  未发现任何 agent 技能目录。" -ForegroundColor Yellow
    Write-Host "    已探测的已知路径："
    foreach ($spec in $AGENT_SPECS) {
        Write-Host ("      {0}  →  {1}" -f $spec.name, (Join-Path $HOME_DIR $spec.dir))
    }
    Write-Host "    若你的 harness 用别的目录，请用:  .\install.ps1 -Target <技能父目录>"
    if (-not $Yes) {
        Write-Host ("    （重跑时加 -Yes 可仍装入 {0}，但你的 agent 未必会读取该目录）" -f (Join-Path $HOME_DIR 'skills'))
        exit 1
    }
    Write-Host "    -Yes 已指定 → 装入 ~\skills（请自行确认 agent 会读取此处）"
    Add-Target (Join-Path $HOME_DIR 'skills') 'fallback'
}

Write-Host "源目录 : $SRC"
Write-Host ("目标数 : {0}（{1}）" -f $PARENTS.Count, ($NAMES -join ' '))
Write-Host ""

$STAMP = Get-Date -Format 'yyyyMMdd-HHmmss'
$OK = 0; $SKIP = 0; $FILL = 0; $WARN = 0
$INSTALLED = New-Object System.Collections.ArrayList

for ($i = 0; $i -lt $PARENTS.Count; $i++) {
    $parent = $PARENTS[$i]
    $name   = $NAMES[$i]
    $dest   = Join-Path $parent $SKILL_NAME

    # 软链 / 联接保护：目标指向别处（如你的私有记忆库）→ 永不写入
    if (Test-Path $dest) {
        $item = Get-Item $dest -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction')) {
            Write-Host ("  ⛔ [{0}] 该技能是链接 → {1}" -f $name, $item.Target)
            Write-Host "      → 跳过且不覆盖（链接指向你自己的记忆库/协议，覆盖会破坏线上数据）"
            $SKIP++
            continue
        }
    }

    # 同源变体检查
    $variants = @(Get-ChildItem -Path $parent -Directory -Filter "$SKILL_NAME*" -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -ne $SKILL_NAME })
    if ($variants.Count -gt 0 -and -not $Force) {
        Write-Host ("  ⚠️  [{0}] 该目录已有同源变体: {1}" -f $name, (($variants | ForEach-Object { $_.Name }) -join ' ')) -ForegroundColor Yellow
        Write-Host "      → 跳过安装（两个变体会让同一个 agent 重复加载记忆协议）"
        Write-Host "      → 想照装请加 -Force；想只留一个请手动处理：$parent\"
        $WARN++; $SKIP++
        continue
    }

    if ($DRY) {
        if (-not (Test-Path $dest))                              { Write-Host "  [dry-run] [$name] → 新增 $dest" }
        elseif (-not (Test-Path (Join-Path $dest 'SKILL.md')))    { Write-Host "  [dry-run] [$name] → 补装（目标已存在但缺 SKILL.md）$dest" }
        elseif ($Update)                                          { Write-Host "  [dry-run] [$name] → 更新协议（保留 memory\）$dest" }
        else                                                      { Write-Host "  [dry-run] [$name] → 已存在，将跳过 $dest" }
        if ($LinkMemory) { Write-Host "             ↳ 并把 memory\ 链到 $LinkMemory" }
        continue
    }

    if (-not (Test-Path $parent)) {
        try { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        catch { Write-Host "  ✗ [$name] 无法创建 $parent" -ForegroundColor Red; continue }
    }

    $skillFile = Join-Path $dest 'SKILL.md'
    if (Test-Path $skillFile) {
        if ($Update) {
            $backupDir = Join-Path $dest '.backups'
            New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dest 'memory\inbox') | Out-Null
            Copy-Item $skillFile (Join-Path $backupDir "SKILL.md.$STAMP") -Force -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $SRC 'SKILL.md') $skillFile -Force
            Write-Host "  ✓ [$name] 已更新协议（保留 memory/；旧版备份在 $backupDir）" -ForegroundColor Green
            $OK++; [void]$INSTALLED.Add($parent)
        } else {
            Write-Host "  – [$name] 已存在，跳过：$dest" -ForegroundColor Yellow
            Write-Host "      想只更新协议、保留你的 memory/ → 重跑加 -Update"
            $SKIP++
        }
    } elseif (Test-Path $dest) {
        Copy-Item (Join-Path $SRC '*') $dest -Recurse -Force
        Write-Host "  ✓ [$name] 目标存在但缺 SKILL.md → 已补装到 $dest" -ForegroundColor Green
        $FILL++; $OK++; [void]$INSTALLED.Add($parent)
    } else {
        Copy-Item -Recurse -Force $SRC $dest
        Write-Host "  ✓ [$name] 已安装到 $dest" -ForegroundColor Green
        $OK++; [void]$INSTALLED.Add($parent)
    }
}

if ($DRY) { Write-Host ""; Write-Host "[dry-run] 结束，未做任何修改。" -ForegroundColor Yellow; exit 0 }

# ---- -LinkMemory：把各目标的 memory\ 统一做成 Junction → 真库（多 agent 共享同一份）----
$LINKED = 0; $LSKIP = 0
if ($LinkMemory) {
    Write-Host ""
    Write-Host "── 统一 MemoryRoot（-LinkMemory）──"
    foreach ($p in $INSTALLED) {
        $dest = Join-Path $p $SKILL_NAME
        $m    = Join-Path $dest 'memory'
        $label = Split-Path $p -Leaf
        $item = Get-Item $m -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction')) {
            $cur = @($item.Target)[0]
            if ($cur -eq $LinkMemory) {
                Write-Host "  – [$label] memory 已指向该库，无需改动"
            } else {
                Write-Host ("  ⚠️  [{0}] memory 已是链接 → {1}" -f $label, $cur) -ForegroundColor Yellow
                Write-Host "      → 不覆盖（可能与你的另一份库绑定）；确实要改请先手动删除该链接"
            }
            $LSKIP++
            continue
        }
        if (Test-Path $m) {
            $backupDir = Join-Path $dest '.backups'
            New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
            $bak = Join-Path $backupDir "memory-template-$STAMP"
            Move-Item -Path $m -Destination $bak -Force -ErrorAction SilentlyContinue
            if (Test-Path $bak) { Write-Host "  ↳ [$label] 原 memory\ 模板已移至 $bak" }
        }
        try {
            New-Item -ItemType Junction -Path $m -Target $LinkMemory -ErrorAction Stop | Out-Null
            Write-Host "  ✓ [$label] memory → $LinkMemory" -ForegroundColor Green
            $LINKED++
        } catch {
            Write-Host ("  ✗ [{0}] 创建 Junction 失败: {1}" -f $label, $_.Exception.Message) -ForegroundColor Red
            Write-Host "      （Junction 通常无需管理员权限；若仍失败请手动执行："
            Write-Host ("         cmd /c mklink /J `"{0}`" `"{1}`"" -f $m, $LinkMemory)
            Write-Host "      )"
        }
    }
    Write-Host ("  统一完成：{0} 处新建链接，{1} 处跳过。" -f $LINKED, $LSKIP)
}

Write-Host ""
Write-Host "── 记忆库根目录（MemoryRoot）解析结果 ──"
if ($LinkMemory) {
    Write-Host "  -LinkMemory 已生效 → 各 agent 的 memory\ 统一指向："
    Write-Host "    $LinkMemory"
    Write-Host "  （多个 agent 共享同一份记忆，任何一方的写入实时互通）"
} elseif ($env:SHARED_AGENT_MEMORY_ROOT) {
    Write-Host "  环境变量已设置 → $env:SHARED_AGENT_MEMORY_ROOT"
    Write-Host "  （多个 agent / 多台设备都将读写这同一份记忆库）"
} else {
    Write-Host "  未设置 SHARED_AGENT_MEMORY_ROOT → 各 agent 读「自己 SKILL.md 所在目录下」的 memory\"
    Write-Host ("  本次实际写入 {0} 处：" -f $INSTALLED.Count)
    foreach ($p in $INSTALLED) { Write-Host ("    {0}\memory" -f (Join-Path $p $SKILL_NAME)) }
    if ($INSTALLED.Count -gt 1) {
        Write-Host "  ⚠️  你装了多个 agent 但各自读各自的库 → 记忆不互通！" -ForegroundColor Yellow
        Write-Host "     想让它们共享同一份，二选一："
        Write-Host "       a) 重跑本脚本并加 -LinkMemory `"<你的真库路径>`"   ← 推荐，无需重启 agent"
        Write-Host "       b) 设置环境变量 SHARED_AGENT_MEMORY_ROOT=<你的库路径> 后再启动 agent"
    }
}

Write-Host ""
Write-Host ("完成（安装/更新 {0} 处，其中补装 {1} 处；跳过 {2} 处，含同源变体告警 {3} 处）。下一步：" -f $OK, $FILL, $SKIP, $WARN)
Write-Host "  1) 编辑任一 memory\persona.md 与 memory\atoms\，填你自己的偏好与事实"
Write-Host "  2) 示例在 memory\atoms\_examples\（priority=1，不会被注入，可整目录删除）"
Write-Host "  3) 体检：bash scripts/doctor.sh    兼容性核对：bash scripts/compat-check.sh"
Write-Host "  4) 各 agent 新开一个会话，问它「是否加载了 shared-agent-memory」；"
Write-Host "     若未出现：确认 SKILL.md 首行为 '---'、文件名正确，并重启 agent。"
