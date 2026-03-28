## ステータス
- Created: `2026-03-20 22:00:00`
- Status: `done`

## 初回依頼
- Date: `2026-03-20 22:00:00`

他の人の GitHub リポジトリをクローンしてきたフォルダが、自分のリポジトリと同じ色・アイコンで表示されている問題を修正する。fex（別ツール）の `001_not-owned-repo-display.md` に記録されているルールと同じ挙動にする。

### 要件
- 自分のリポジトリ → 今まで通り（地球儀・鍵・Gitアイコン、状態に応じた色）
- 他の人のリポジトリ → クラウドダウンロードアイコン（U+F0ED）・色なし・↑↓ なし
- 判定方法：リモート URL に自分の GitHub ユーザー名が含まれるかどうか（`~/.config/gh/hosts.yml` から取得）


## 実装01
- Date: `2026-03-20 22:00:00`
- Model: `Claude-Sonnet-4.6`

### 実装内容

`gh-visibility.sh` を修正：
- has_remote チェックの直後に not-owned チェックを追加
- `~/.config/gh/hosts.yml` から GitHub ユーザー名を取得
- リモート URL にユーザー名が含まれない場合は `\xef\x83\xad`（U+F0ED クラウドダウンロード）を返して終了

`statusline-claude.sh` を修正：
- `git_not_owned=false` を追加
- git セクションの冒頭で `has_remote` を計算し、リモートがある場合に not-owned チェックを実行
- not-owned の場合: `git_not_owned=true`・`git_line_color=""` にセット
- `! $git_not_owned` の場合のみ、従来の dirty state チェック（porcelain/unpushed/behind）を実行
- 表示側（line2）は変更なし。`git_unpushed=0`・`git_behind=0` のまま（初期値）なので ↑↓ は出ない

### 実装後の確認項目とフィードバック

- 他の人のリポジトリを開いたとき、クラウドダウンロードアイコン・色なし・↑↓ なしで表示される →
- 自分のリポジトリは今まで通りの色・アイコンで表示される →
