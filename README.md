# claude-statusline

A custom status line script for [Claude Code](https://claude.ai/code) that displays context usage, rate limit progress bars, and git information.

---

Claude Code のカスタムステータスラインスクリプトです。コンテキスト使用率・レートリミットのプログレスバー・git 情報などを表示します。

---

## Preview / プレビュー

```
~/00_Home_Local/20_dev/claude-statusline
git: claude-statusline [main]
Claude Sonnet 4.6 │ CTX 12%
5h  ███░░░░░░░  34%
7d  █░░░░░░░░░  8%
```

---

## What it shows / 表示内容

| Line | Content (EN) | 内容 (JP) |
|------|-------------|-----------|
| 1 | Current directory path | 現在のディレクトリパス |
| 2 | Git repo name and branch (only inside a git repo) | git リポジトリ名とブランチ名（git リポジトリ内のみ） |
| 3 | Model name \| Context usage % | モデル名 \| コンテキスト使用率 |
| 4 | 5-hour rate limit progress bar | 5 時間レートリミットのプログレスバー |
| 5 | 7-day rate limit progress bar | 7 日間レートリミットのプログレスバー |

Colors change based on usage: green (< 50%) → yellow (50–79%) → red (≥ 80%)

使用率に応じて色が変わります：緑（50% 未満）→ 黄（50〜79%）→ 赤（80% 以上）

---

## Requirements / 必要なもの

- macOS
- [Claude Code](https://claude.ai/code)
- `jq`
- `curl`
- `bash`

`jq` のインストール（未インストールの場合）:
```bash
brew install jq
```

---

## Setup / セットアップ

### 1. Clone / クローン

```bash
git clone https://github.com/noki1213/claude-statusline.git
cd claude-statusline
chmod +x statusline-claude.sh
```

### 2. Configure Claude Code / Claude Code に設定する

Add the following to `~/.claude/settings.json`:

`~/.claude/settings.json` に以下を追加します：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/claude-statusline/statusline-claude.sh"
  }
}
```

`/path/to/claude-statusline/` の部分は実際のパスに変更してください。

---

## Notes / 備考

- Rate limit info is fetched by sending a minimal request to the Anthropic API using the Claude Haiku model. Results are cached for 6 minutes to avoid excessive API calls.
- レートリミット情報は Claude Haiku モデルへの最小リクエストで取得します。API 呼び出しを抑えるため、結果は 6 分間キャッシュされます。
- Credentials are read from the macOS keychain (set up automatically by Claude Code).
- 認証情報は macOS のキーチェーンから読み取ります（Claude Code が自動で設定）。

---

## Reference / 参考

- [loadbalance-sudachi-kun/claude-code-statusline](https://github.com/loadbalance-sudachi-kun/claude-code-statusline)
