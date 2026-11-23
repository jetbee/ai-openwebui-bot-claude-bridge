# personas.json（見本: personas.example.json）を読み、担当ごとに tmux の新しいウィンドウを作って
# start-session.ps1 を起動する。psmux/tmux のパネルを 1 つずつ手で開く代わりに、1 回の実行でまとめて立ち上げる。
#
# 前提:
# - tmux（または互換の多重化ツール）が PATH にあること。tmux は detached（裏）でも各ウィンドウに
#   本物の疑似端末（PTY）を割り当てるので、`--dangerously-load-development-channels` の
#   「対話できる端末が必要」という制約も、画面を見ていない状態のままで満たせる。
# - 初回のみ、各セッションで Claude Code の「I am using this for local development」の確認が出る。
#   自動化はしていないので、起動直後に一度ずつ tmux の画面を見て選ぶこと。
# - 踏み台・Redmine などの共有リソースへ同時に大量接続しないよう、既定で 1 担当ずつ間隔を空けて起動する。
#
# 使い方（例）:
#   .\launch-all.ps1 -PersonasFile personas.json -TmuxSession mybots
#   .\launch-all.ps1 -PersonasFile personas.json -TmuxSession mybots -DryRun   # 起動せず、実行内容だけ表示

param(
  [string]$PersonasFile = "personas.json",
  [Parameter(Mandatory = $true)][string]$TmuxSession,
  [int]$DelaySeconds = 5,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
if (-not $DryRun -and -not (Get-Command tmux -ErrorAction SilentlyContinue)) {
  throw "tmux が見つかりません。PATH を確認してください（-DryRun なら tmux が無くても内容だけ確認できます）。"
}
if (-not (Test-Path $PersonasFile)) {
  throw "見つかりません: $PersonasFile （personas.example.json をコピーして作ってください）"
}
$personas = Get-Content $PersonasFile -Raw | ConvertFrom-Json
if (-not $personas -or $personas.Count -eq 0) { throw "$PersonasFile に担当が1件もありません" }

$startScript = Join-Path $PSScriptRoot "start-session.ps1"
$sessionExists = $false
if (-not $DryRun) {
  tmux has-session -t $TmuxSession 2>$null
  $sessionExists = ($LASTEXITCODE -eq 0)
}

foreach ($p in $personas) {
  if (-not $p.name -or -not $p.userPrefix -or -not $p.baseUrl) {
    Write-Warning "name / userPrefix / baseUrl が欠けている項目をスキップしました: $($p | ConvertTo-Json -Compress)"
    continue
  }
  # 引数は配列のまま tmux に渡す（シェルのクォートを経由しないので、特殊文字があっても壊れにくい）
  $args = @(
    "powershell", "-NoExit", "-File", $startScript,
    "-Name", $p.name, "-UserPrefix", $p.userPrefix, "-BaseUrl", $p.baseUrl
  )
  if ($p.prompt) { $args += @("-Prompt", $p.prompt) }

  if ($DryRun) {
    "[dry-run] window '$($p.name)': " + ($args -join ' ')
    continue
  }

  if (-not $sessionExists) {
    tmux new-session -d -s $TmuxSession -n $p.name -- @args
    $sessionExists = $true
  } else {
    tmux new-window -t $TmuxSession -n $p.name -- @args
  }
  Write-Host "起動しました: $($p.name)（$($DelaySeconds)秒待ってから次へ）"
  if ($p -ne $personas[-1]) { Start-Sleep -Seconds $DelaySeconds }
}

if (-not $DryRun) {
  "完了。tmux attach -t $TmuxSession で確認してください。初回は各ウィンドウで確認ダイアログを選ぶ必要があります。"
}
