# Claude Code Statusline

Claude Code のステータスラインに、モデル情報・コンテキスト使用率・レートリミット状況を3行で表示するシェルスクリプトです。

詳しい解説は Zenn 記事をご覧ください：
**[Claude Codeのステータスラインに使用率を出す](https://zenn.dev/suthio/articles/f832922e18f994)**

## Screenshot

```
🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
```

## 表示内容

| 行 | 内容 |
|----|------|
| 1行目 | モデル名、コンテキストウィンドウ使用率、追加/削除行数、git ブランチ名 |
| 2行目 | 5時間レートリミット使用率（プログレスバー + リセット時刻） |
| 3行目 | 7日間レートリミット使用率（プログレスバー + リセット時刻） |

## カラーリング

使用率に応じて色が変わります：

| 範囲 | 色 | カラーコード |
|------|-----|-------------|
| 0-49% | 緑 | `#97C9C3` |
| 50-79% | 黄 | `#E5C07B` |
| 80-100% | 赤 | `#E06C75` |
| 区切り文字 | グレー | `#4A585C` |

## インストール

### 1. スクリプトを配置

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

### 2. settings.json を設定

`~/.claude/settings.json` に以下を追加：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

### 3. Claude Code を再起動

設定を反映するため、Claude Code を再起動してください。

## 動作要件

- macOS（`security` コマンドでキーチェーンからトークンを取得）
- `jq`（JSON パース）
- `curl`（API 呼び出し）
- `git`（ブランチ名・差分取得）

## レートリミット情報の取得

macOS キーチェーンから `Claude Code-credentials` の OAuth トークンを取得し、`https://api.anthropic.com/api/oauth/usage` API を呼び出します。

- レスポンスの `five_hour.utilization` と `seven_day.utilization` を使用
- `/tmp/claude-usage-cache.json` に360秒間キャッシュ
- API 失敗時は古いキャッシュをフォールバック使用

## 入力仕様

スクリプトは stdin から以下の JSON を受け取ります（Claude Code が自動的に渡します）：

```json
{
  "model": { "display_name": "Opus 4.6" },
  "context_window": { "used_percentage": 25 },
  "cwd": "/path/to/working/directory"
}
```

## License

MIT
