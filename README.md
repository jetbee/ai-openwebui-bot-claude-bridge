# ai-openwebui-bot-claude-bridge

A small MCP bridge between an [Open WebUI](https://github.com/open-webui/open-webui) **channel** and
[Claude Code](https://claude.com/claude-code)'s experimental **Channels** feature. It lets a Claude Code
session act like a chat bot: it reads new messages posted to an Open WebUI channel and replies there,
without needing permission relaying or a custom frontend.

日本語の説明は [下のセクション](#日本語) にあります。

## How it works

```
Open WebUI channel (your Open WebUI instance)
   ↑ reply  (POST /api/v1/channels/{id}/messages/post, as the bot user)
   ↓ poll   (GET  /api/v1/channels/{id}/messages every few seconds, allow-listed senders only)
bridge.mjs (an MCP "channel" server, spawned by Claude Code as a child process)
   ↕ stdio
Claude Code (claude --dangerously-load-development-channels server:<name>)
```

- Receiving is polling-based (a few seconds interval) by design — few moving parts, hard to break.
- There is no permission relay: production/destructive actions are never approved from the chat channel.
  Claude Code's own permission prompts are answered at the terminal, as usual.
- A lightweight "typing…" indicator is shown via a second, authenticated Socket.IO connection, with a
  plain message fallback if that's unavailable.

## Setup

1. **Node.js 18+ (LTS)** must be installed.
2. `npm install` in this folder.
3. Create an Open WebUI user for the bot, create a channel with the same name, add the bot user to it,
   and generate an API key for that user. Save the key to a file (e.g.
   `%USERPROFILE%\.openwebui\yourbot_api-key` on Windows, or `~/.openwebui/yourbot_api-key`) — **never**
   commit the key value anywhere.
4. Copy `config.example.json` to `config.json` and fill in `baseUrl`, `keyFile`, and `channelName`.
5. Find sender IDs: `node bridge.mjs --list-senders` (reads `config.json` by default).
6. Copy `allowlist.example.json` to `allowlist.json` and add the `user_id`s you want to allow.
   Leaving `user_ids` empty means nobody is let through.
7. Copy `bridge.mcp.example.json` to `bridge.mcp.json`, fix the absolute path to `bridge.mjs`, then launch:
   ```
   claude --mcp-config bridge.mcp.json --dangerously-load-development-channels server:openwebui-bridge
   ```
   Accept the "I am using this for local development" confirmation dialog.

### Multiple personas / channels on one machine

If you want several independent bot personalities (each with its own Open WebUI user, channel, and
allow-list), use `start-session.ps1` as a starting point: it generates a per-persona `configs/<name>.json`
and `configs/<name>.mcp.json` and launches `claude` for you. See `configs/example-persona.*.json` for the
shape it produces. The script's `$Prompt` default is intentionally minimal — write your own system prompt
for your own workflow (escalation rules, who to contact, what the persona is responsible for, etc.).

Running `start-session.ps1` once per persona by hand (one tmux/terminal pane at a time) works, but doesn't
scale past a couple of personas. `launch-all.ps1` automates this: it reads a `personas.json` (see
`personas.example.json`) listing every persona, and opens one `tmux` window per persona itself — `tmux`
gives each window a real pseudo-terminal even when nobody is attached, which is exactly what
`--dangerously-load-development-channels` needs.

```powershell
.\launch-all.ps1 -PersonasFile personas.json -TmuxSession mybots           # launches everything
.\launch-all.ps1 -PersonasFile personas.json -TmuxSession mybots -DryRun   # preview only, no tmux needed
```

Each persona still needs its "I am using this for local development" dialog answered once per window —
that part isn't automated.

## Configuration reference (`config.json`)

| Key | Meaning |
|---|---|
| `baseUrl` | Base URL of your Open WebUI instance |
| `keyFile` | Path to a file holding the bot's API key (supports `%USERPROFILE%`) |
| `channelName` | Channel name, also used as the bot's display name |
| `serverName` | MCP server name shown to Claude Code (optional) |
| `pollMs` | Polling interval in ms (default 3000) |
| `fetchLimit` | How many recent messages to fetch per poll (default 30) |
| `requireMention` | If `true`, only messages that `@mention` the bot are forwarded (default `false`) |
| `botName` / `botUserId` | Override how the bot recognizes mentions of itself |
| `allowAllMembers` | If `true` (default), every channel member except the bot is forwarded; set `false` to use `allowlist.json`'s `user_ids` strictly instead |
| `approverMention` | Optional name to `@mention` at the end of replies that ask for a go/no-go decision |
| `loginFile` | Optional `{"email","password"}` file used only for the Socket.IO "typing" indicator |
| `attachments` | Default `true`. Download files attached to channel posts (images etc.) into `attachments/` and append their local paths to the message so Claude can open them with its Read tool. Set `false` to disable |
| `attachmentMaxFiles` / `attachmentMaxBytes` | Per-post file count limit (default 10) and per-file size limit (default 20 MB). Files older than 7 days are purged automatically |

## Security notes

- Secrets (API keys, login credentials) are never read from the repo — only from files outside it,
  referenced by path. `.gitignore` excludes real `config.json`, `allowlist.json`, `bridge.mcp.json`,
  per-persona configs, runtime state and delivery logs.
- Permission relaying is intentionally not implemented. A channel message can never itself authorize a
  destructive action; only the human at the actual terminal can.
- Keep your allow-list small and trusted — anyone on it can effectively prompt the attached Claude Code
  session.

## Known limitations

- `--dangerously-load-development-channels` only works in an interactive terminal session (it's ignored
  under `-p` / non-interactive invocations).
- Your organization's `channelsEnabled` setting (if managed) takes precedence over this bridge.
- If messages don't arrive, check `claude --debug` logs (`~/.claude/debug/`) for `not in --channels list`.

## License

MIT — see [LICENSE](LICENSE).

---

## 日本語

Open WebUI の**チャンネル**と、Claude Code の実験的機能である**Channels**をつなぐ、小さなMCP橋渡し役です。
Claude Code セッションをチャットボットのように動かせます。Open WebUI のチャンネルに投稿された新着メッセージを
読み、同じチャンネルに返信します。権限の中継や専用フロントエンドは不要です。

### 仕組み

```
Open WebUI のチャンネル（あなたのOpen WebUI環境）
   ↑ 返信（POST /api/v1/channels/{id}/messages/post、ボットのユーザーとして）
   ↓ 受信（数秒おきに GET /api/v1/channels/{id}/messages。許可リストの送信者だけ）
bridge.mjs（MCP の channel サーバー、Claude Code が子プロセスとして起動）
   ↕ stdio
Claude Code（claude --dangerously-load-development-channels server:<name>）
```

- 受信はポーリング方式（数秒間隔）。部品が少なく、壊れにくいための設計判断です。
- 権限の中継（permission relay）はありません。本番・破壊的な操作の許可を、チャンネルの発言だけで
  成立させることはできません。Claude Code 自体の許可ダイアログは、従来どおり端末で答えます。
- 「入力中…」の表示は、別途ログインしたSocket.IO接続で出します。使えないときは、普通の投稿で代用します。

### セットアップ

1. **Node.js 18以上（LTS）**が必要です。
2. このフォルダで `npm install`。
3. ボット用の Open WebUI ユーザーを作り、同名のチャンネルを作って、そのユーザーをチャンネルに追加し、
   APIキーを発行します。キーの値はファイルに保存してください（例: Windowsなら
   `%USERPROFILE%\.openwebui\yourbot_api-key`、それ以外なら `~/.openwebui/yourbot_api-key`）。
   **値はどこにもコミットしないでください。**
4. `config.example.json` を `config.json` にコピーし、`baseUrl`・`keyFile`・`channelName` を埋めます。
5. 送信者IDの確認: `node bridge.mjs --list-senders`（既定で `config.json` を読みます）。
6. `allowlist.example.json` を `allowlist.json` にコピーし、許可したい `user_id` を追加します。
   `user_ids` が空のままだと、誰の投稿も渡りません。
7. `bridge.mcp.example.json` を `bridge.mcp.json` にコピーし、`bridge.mjs` への絶対パスを直してから起動します:
   ```
   claude --mcp-config bridge.mcp.json --dangerously-load-development-channels server:openwebui-bridge
   ```
   「I am using this for local development」の確認ダイアログを選んでください。

#### 複数の担当（ペルソナ）・チャンネルを1台で動かす場合

複数の独立したボット人格（それぞれ専用のOpen WebUIユーザー・チャンネル・許可リストを持つ）を動かしたい場合は、
`start-session.ps1` を出発点にしてください。担当ごとの `configs/<名前>.json` と `configs/<名前>.mcp.json` を
自動生成し、`claude` を起動します。生成される形は `configs/example-persona.*.json` を参照してください。
スクリプトの `$Prompt` の既定値は意図的に最小限にしてあります。自分の運用（エスカレーションのルール、
連絡先、その担当の責任範囲など）に合わせて書き換えてください。

`start-session.ps1` を担当の数だけ手で（tmux/端末のパネルを1つずつ開いて）実行する方法は、担当が数人のうちは
問題ありませんが、数が増えると辛くなります。`launch-all.ps1` はこれを自動化します。`personas.json`
（見本: `personas.example.json`）に担当を列挙しておけば、担当ごとに `tmux` のウィンドウを自分で作って起動します。
`tmux` は、誰もアタッチしていない状態（detached）でも各ウィンドウに本物の疑似端末（PTY）を割り当てるので、
`--dangerously-load-development-channels` が要求する「対話できる端末」の条件もそのまま満たせます。

```powershell
.\launch-all.ps1 -PersonasFile personas.json -TmuxSession mybots           # 全部起動する
.\launch-all.ps1 -PersonasFile personas.json -TmuxSession mybots -DryRun   # 起動せず内容だけ確認（tmux不要）
```

各担当ごとに「I am using this for local development」の確認は、ウィンドウごとに1回ずつ必要です
（そこまでは自動化していません）。

### 設定リファレンス（`config.json`）

| キー | 意味 |
|---|---|
| `baseUrl` | Open WebUI インスタンスのベースURL |
| `keyFile` | ボットのAPIキーを保存したファイルのパス（`%USERPROFILE%` 使用可） |
| `channelName` | チャンネル名。ボットの表示名としても使う |
| `serverName` | Claude Code に見えるMCPサーバー名（任意） |
| `pollMs` | ポーリング間隔（ミリ秒、既定3000） |
| `fetchLimit` | 1回のポーリングで取得する件数（既定30） |
| `requireMention` | `true` にすると、ボットへの`@メンション`があるメッセージだけを渡す（既定 `false`） |
| `botName` / `botUserId` | 自分へのメンション判定に使う名前・IDの上書き |
| `allowAllMembers` | 既定 `true`。チャンネルメンバー全員（自分以外）を渡す。`false` にすると `allowlist.json` の `user_ids` だけに厳密に従う |
| `approverMention` | 許可・判断を求める返信の末尾に付ける `@メンション` 名（任意） |
| `loginFile` | 「入力中…」表示専用の `{"email","password"}` ファイル（任意） |
| `attachments` | 既定 `true`。チャンネルの投稿に添付されたファイル（画像など）を `attachments/` にダウンロードし、ローカルのパスを本文に付けて渡す（Claude は Read ツールで開ける）。`false` で無効 |
| `attachmentMaxFiles` / `attachmentMaxBytes` | 1 投稿あたりの件数の上限（既定 10）と、1 ファイルの大きさの上限（既定 20 MB）。7 日より古いファイルは自動で削除 |

### セキュリティ上の注意

- 秘密情報（APIキー・ログイン情報）はリポジトリの中からは読み込みません。常にリポジトリ外のファイルを、
  パスで参照する形です。`.gitignore` で、実際の `config.json`・`allowlist.json`・`bridge.mcp.json`・
  担当ごとの設定・実行時の状態ファイル・配信ログを除外しています。
- 権限の中継はあえて実装していません。チャンネルの発言だけで破壊的な操作が許可されることはなく、
  実際の端末にいる人だけが許可できます。
- 許可リストは信頼できる人だけに、少人数で保つことをお勧めします。リストに入っている人は、実質的に
  接続先のClaude Codeセッションに指示を出せます。

### 既知の制限

- `--dangerously-load-development-channels` は対話できる端末セッションでしか効きません（`-p` や
  非対話実行では無視されます）。
- 組織側で `channelsEnabled` が管理されている場合、その設定がこの橋渡し役より優先されます。
- メッセージが届かないときは、`claude --debug` のログ（`~/.claude/debug/`）に
  `not in --channels list` が出ていないか確認してください。

### ライセンス

MIT — [LICENSE](LICENSE) を参照してください。
