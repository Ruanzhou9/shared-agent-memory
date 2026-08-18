<#
    ============================================================
    Shared Agent Memory · 一键安装脚本 (PowerShell / Windows)
    与 install.sh 对应：探测当前环境可用的 agent 类型，
    把 shared-agent-memory 拷到正确的技能根目录。

    用法:
        powershell -ExecutionPolicy Bypass -File install.ps1
        .\install.ps1 -DryRun
        .\install.ps1 -Target "C:\path\to\skills"
    ============================================================
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Target = ""
)

$ErrorActionPreference = 'Stop'
$SRC = Join-Path $PSScriptRoot 'shared-agent-memory'
$DRY = [bool]$DryRun
$TARGET = $Target
$HOME_DIR = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if (-not $HOME_DIR) { $HOME_DIR = '.' }

if (-not (Test-Path (Join-Path $SRC 'SKILL.md'))) {
    Write-Host "✗ 未找到 $SRC\SKILL.md，请在仓库根目录运行本脚本。" -ForegroundColor Red
    exit 1
}

# ---- 探测目标父目录（Windows 常见 agent 约定目录，命中第一个）----
function Get-DetectDest {
    if ($TARGET) { return $TARGET }
    # 与 install.sh 对齐：存在 .skills 目录或对应父目录即命中
    $probe = @(
        @{ dir = '\.claude\skills';   parent = '\.claude' },
        @{ dir = '\.hermes\skills';   parent = '\.hermes' },
        @{ dir = '\.openclaw\skills'; parent = '\.openclaw' },
        @{ dir = '\.codex\skills';    parent = '\.codex' },
        @{ dir = '\.dsh\skills';      parent = '\.dsh' }
    )
    foreach ($p in $probe) {
        if (Test-Path (Join-Path $HOME_DIR $p.dir)) { return Join-Path $HOME_DIR $p.dir }
        if (Test-Path (Join-Path $HOME_DIR $p.parent)) { return Join-Path $HOME_DIR $p.dir }
    }
    # 都没有：装到用户目录下的 skills
    return Join-Path $HOME_DIR 'skills'
}

$DEST_PARENT = Get-DetectDest
$DEST = Join-Path $DEST_PARENT 'shared-agent-memory'

Write-Host "源目录  : $SRC"
Write-Host "目标位置: $DEST"

if ($DRY) {
    Write-Host "[dry-run] 结束，未安装。" -ForegroundColor Yellow
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $DEST_PARENT | Out-Null
} catch {
    Write-Host "✗ 无法创建目标目录: $DEST_PARENT" -ForegroundColor Red
    exit 1
}

if (Test-Path $DEST) {
    Write-Host "⚠️ 目标已存在，未覆盖: $DEST" -ForegroundColor Yellow
} else {
    Copy-Item -Recurse -Force $SRC $DEST
    Write-Host "✓ 已安装到 $DEST" -ForegroundColor Green
}

Write-Host ""
Write-Host "完成。请新开一个 agent 会话，询问它是否加载了 shared-agent-memory。"
Write-Host "若未出现：确认 $DEST\SKILL.md 首行为 '---'，并重启 agent。"
