# 担当のセッションを、専用の Open WebUI ユーザー・専用のチャンネルにつないで起動する。
# 対話できる端末（Windows Terminal など）で実行する。開発用フラグの確認ダイアログが出るので
# 「I am using this for local development」を選ぶ。
#
# 設計: 1 つのチャンネルに 1 つの担当エージェントと、1 つの専用ユーザー。
#   名前をそろえる:  Open WebUI のユーザー名 = チャンネル名 = <UserPrefix>-<Name>
#   キーのファイル:  %USERPROFILE%\.openwebui\<UserPrefix>-<Name>_api-key   （値はどこにも書かない）
# 事前に、Open WebUI で、上のユーザーと、同名のチャンネルを作り、ユーザーをチャンネルに追加し、そのユーザーで API キーを作ってファイルに置くこと。
#
# このスクリプトは、設定ファイル（config.json 相当）と MCP 設定を自動生成し、claude を起動するところまでを行う。
# $prompt は最小限の例なので、自分のワークフローに合わせて書き換えること（引き継ぎ書・許可ルール・連絡先など）。
#
# 使い方（例）:
#   .\start-session.ps1 -Name work -UserPrefix yourbot -BaseUrl http://YOUR-OPENWEBUI-HOST:3000
#   .\start-session.ps1 -Name work -UserPrefix yourbot -BaseUrl http://YOUR-OPENWEBUI-HOST:3000 -DryRun   # 起動せず、生成内容だけ確認

param(
  [Parameter(Mandatory = $true)][string]$Name,          # 担当の名前（例: work）
  [Parameter(Mandatory = $true)][string]$UserPrefix,     # Open WebUI 側のユーザー名・チャンネル名の接頭辞（例: yourbot）
  [Parameter(Mandatory = $true)][string]$BaseUrl,        # Open WebUI の URL（例: http://localhost:3000）
  [string]$Prompt = "",                                   # 起動時の最初の指示（省略時は簡単な既定文）
  [switch]$DryRun                                        # 起動せず、作る設定と最初の指示だけを表示する
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$safe = $Name -replace '[^A-Za-z0-9_.-]', '_'
$Channel = "$UserPrefix-$safe"

# 設定ファイル（秘密は入れない。キーの置き場所だけ）を configs\ に作る
$cfgDir = Join-Path $root "configs"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$cfgPath = Join-Path $cfgDir "$safe.json"
$mcpPath = Join-Path $cfgDir "$safe.mcp.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$cfg = [ordered]@{
  baseUrl     = $BaseUrl
  keyFile     = "%USERPROFILE%\.openwebui\$Channel`_api-key"
  channelName = $Channel
  serverName  = "openwebui-$safe"
  pollMs      = 3000
  fetchLimit  = 30
}
[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), $utf8)

$mcp = [ordered]@{
  mcpServers = [ordered]@{
    "openwebui-$safe" = [ordered]@{
      command = "node"
      args    = @((Join-Path $root "bridge.mjs"))
      env     = [ordered]@{ OPENWEBUI_BRIDGE_ACTIVE = "1"; OPENWEBUI_BRIDGE_CONFIG = $cfgPath }
    }
  }
}
[IO.File]::WriteAllText($mcpPath, ($mcp | ConvertTo-Json -Depth 6), $utf8)

# キーのファイルがあるか（値は読まない）
$keyPath = (($cfg.keyFile) -replace '%USERPROFILE%', $env:USERPROFILE)
if (-not (Test-Path $keyPath)) {
  Write-Warning "キーのファイルがありません: $keyPath （ユーザー $Channel の API キーを作って置いてください。無いと、チャンネルとの連携は動きません）"
}

if (-not $Prompt) {
  $Prompt = "あなたは「$Name」の担当です。このチャンネルのメッセージに、reply ツールで日本語で答えてください。反応すると決めたら、最初に typing ツールを呼んでください。パスワード・API キー・秘密鍵などの値は書かないでください。"
}

if ($DryRun) {
  "--- DryRun（起動しません）"
  "セッション名 : $safe"
  "チャンネル   : $Channel（ユーザー名も同じ）"
  "キーのファイル: $keyPath （あり: " + (Test-Path $keyPath) + "）"
  "設定ファイル : $cfgPath"
  "MCP 設定     : $mcpPath"
  "最初の指示   :"
  $Prompt
  return
}

# プロンプトは先頭に置く（後ろのフラグが複数の値を取るため）
claude $Prompt --name $safe --mcp-config $mcpPath --dangerously-load-development-channels "server:openwebui-$safe"
