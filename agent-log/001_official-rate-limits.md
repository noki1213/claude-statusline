## ステータス
- Created: `2026-03-20 14:23:53`
- Status: `done`

## 初回依頼
- Date: `2026-03-20 14:23:53`

Claude Code v2.1.80 で公式に追加された `rate_limits` フィールドを使い、
5時間・7日間のレートリミット表示を非公式の方法から公式の方法に切り替える。

### 変更前の問題点

`fetch_usage` 関数が以下の非公式な方法でレートリミットを取得していた：

1. キーチェーンから Claude Code の認証トークンを取り出す
2. Haiku モデルに curl で最小リクエストを送る
3. レスポンスヘッダー（`anthropic-ratelimit-unified-5h-utilization` など）から使用率を読み取る
4. `/tmp/claude-usage-cache.json` にキャッシュして 360 秒間使い回す

問題：API コストがかかる・認証トークンをスクリプトが直接扱う・非公式ヘッダーの利用で規約違反の可能性。

### 変更後

v2.1.80 のリリースで、Claude Code がステータスラインスクリプトに渡す JSON に
`rate_limits` フィールドが公式に追加された。

渡ってくる JSON の構造（実測値）：
```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 6,
      "resets_at": 1774000800
    },
    "seven_day": {
      "used_percentage": 81,
      "resets_at": 1774317600
    }
  }
}
```

注意点：ブログ記事（nyosegawa.com）では `resets_at` が ISO 8601 形式の文字列
（例：`"2026-03-20T15:00:00Z"`）と書かれていたが、実際にはエポック秒の整数で渡ってくる。


## 実装01
- Date: `2026-03-20 14:23:53`
- Model: `claude-sonnet-4-6`

### 実装内容

削除した処理（90行ぶん）：
- `fetch_usage` 関数（curl でAPIを叩く処理）
- `load_usage` 関数（キャッシュから読み込む処理）
- キャッシュファイル `/tmp/claude-usage-cache.json` の読み書き処理
- `to_pct` 関数（0.0〜1.0 の小数を % に変換していた）

追加した処理（23行ぶん）：
- jq で `rate_limits.five_hour.used_percentage` / `resets_at` を読み取る
- jq で `rate_limits.seven_day.used_percentage` / `resets_at` を読み取る
- `iso_to_epoch` 関数（ISO 8601 → エポック秒の変換）を追加 ※後で削除

デバッグ用に一時的に `echo "$input" > /tmp/statusline-debug.json` を追加し、
実際に渡ってくる JSON を確認してから削除した。

### 実装後の確認項目とフィードバック

- `resets_at` の形式が ISO 8601 ではなくエポック秒だったため、`iso_to_epoch` 関数が不要になった → 実装02 で対応


## 実装02
- Date: `2026-03-20 14:26:45`
- Model: `claude-sonnet-4-6`

### 実装内容

実際に渡ってくる JSON を確認したところ、`resets_at` がエポック秒の整数だったため、
`iso_to_epoch` 関数（ISO 8601 → エポック秒の変換）を削除した。

`fast-forward` マージで main に取り込んだ。

### 実装後の確認項目とフィードバック

- 正常動作を確認 → OK
