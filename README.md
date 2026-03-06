# Claude Code Statusline

Claude Code のステータスラインに、モデル情報・コンテキスト使用率・レートリミット状況をリアルタイム表示するシェルスクリプトです。

詳しい解説は Zenn 記事をご覧ください：
**[Claude Codeのステータスラインに使用率を出す](https://zenn.dev/suthio/articles/f832922e18f994)**

## スクリーンショット

```
🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
```

## 表示内容

### 1行目：セッション情報

| 項目 | 説明 |
|------|------|
| 🤖 モデル名 | 使用中のモデル（Opus 4.6, Sonnet 4.5 等） |
| 📊 コンテキスト使用率 | コンテキストウィンドウの消費率（200K トークン中） |
| ✏️ 変更行数 | セッション内の累計 `+追加/-削除` 行数 |
| 🔀 ブランチ名 | 作業ディレクトリの git ブランチ（git リポジトリ内のみ表示） |

### 2行目：5時間レートリミット

5時間ウィンドウの使用率をプログレスバー（▰▱ × 10セグメント）で表示します。リセット時刻を Asia/Tokyo タイムゾーンで併記します。

### 3行目：7日間レートリミット

7日間ウィンドウの使用率を同様のプログレスバーで表示します。

## カラーリング

使用率に応じて自動的に色が変わります：

| 範囲 | 色 | カラーコード |
|------|-----|-------------|
| 0-49% | 緑 | `#97C9C3` |
| 50-79% | 黄 | `#E5C07B` |
| 80-100% | 赤 | `#E06C75` |
| 区切り文字 | グレー | `#4A585C` |

## インストール

### 1. リポジトリをクローン

```bash
git clone https://github.com/loadbalance-sudachi-kun/claude-code-statusline.git
cd claude-code-statusline
```

### 2. スクリプトを配置

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
```

### 3. settings.json を設定

`~/.claude/settings.json` に以下を追加してください：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

既に `settings.json` がある場合は、`"statusLine"` キーだけをマージしてください。

### 4. Claude Code を再起動

設定を反映するため、Claude Code のセッションを再起動してください。

## 動作要件

| 要件 | 用途 |
|------|------|
| macOS | `security` コマンドでキーチェーンから OAuth トークンを取得 |
| `jq` | JSON パース |
| `curl` | API 呼び出し |
| `git` | ブランチ名取得 |
| Claude Code の OAuth 認証 | API キー認証ではなく OAuth ログインが必要 |

`jq` が未インストールの場合：

```bash
brew install jq
```

## アーキテクチャ

### データソース

このスクリプトは2つのソースからデータを取得します：

#### 1. stdin（Claude Code が自動提供）

Claude Code はステータスラインコマンドの stdin に以下の JSON を渡します：

```json
{
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6" },
  "version": "2.1.69",
  "cwd": "/path/to/working/directory",
  "context_window": {
    "used_percentage": 48,
    "remaining_percentage": 52,
    "context_window_size": 200000
  },
  "cost": {
    "total_cost_usd": 4.23,
    "total_lines_added": 162,
    "total_lines_removed": 34
  },
  "workspace": {
    "current_dir": "/path/to/current",
    "project_dir": "/path/to/project"
  }
}
```

モデル名・コンテキスト使用率・変更行数はここから取得します。

#### 2. Haiku プローブ（レートリミット情報）

レートリミット情報は Anthropic API のレスポンスヘッダーから取得します。具体的には、Haiku に `max_tokens: 1` の最小リクエストを送信し、レスポンスヘッダーに含まれる以下の値を読み取ります：

```
anthropic-ratelimit-unified-5h-utilization: 0.28
anthropic-ratelimit-unified-5h-reset: 1772791200
anthropic-ratelimit-unified-7d-utilization: 0.59
anthropic-ratelimit-unified-7d-reset: 1772784000
```

> **なぜ `/api/oauth/usage` を使わないのか？**
>
> Anthropic は `/api/oauth/usage` という REST エンドポイントも提供していますが、アカウントのレートリミットに達している状態ではこのエンドポイント自体が 429 を返します。つまり、使用率を最も確認したいタイミングで使えません。Haiku プローブ方式なら、アカウントがレートリミット中でもレスポンスヘッダーにリミット情報が含まれるため、確実に取得できます。

### キャッシュ

- キャッシュファイル: `/tmp/claude-usage-cache.json`
- キャッシュ TTL: 360秒（6分）
- API 失敗時は古いキャッシュをフォールバック使用
- 1プローブあたりのコスト: 約 $0.00001（Haiku 1トークン）

### 認証

macOS キーチェーンの `Claude Code-credentials` から OAuth トークンを取得します。Claude Code に OAuth でログインしていれば自動的に利用可能です。

API 呼び出しには `anthropic-beta: oauth-2025-04-20` ヘッダーが必要です（OAuth トークンで Messages API を利用するため）。

## カスタマイズ

### キャッシュ TTL を変更する

スクリプト内の `CACHE_TTL=360` を変更してください（単位: 秒）。値を小さくするとより頻繁に API を呼びますが、Haiku のコストは極めて低いため実用上問題ありません。

### タイムゾーンを変更する

スクリプト内の `TZ="Asia/Tokyo"` を任意のタイムゾーンに変更してください。

### カラーを変更する

スクリプト冒頭の ANSI カラー定義を変更してください：

```bash
GREEN=$'\e[38;2;151;201;195m'   # RGB(151, 201, 195)
YELLOW=$'\e[38;2;229;192;123m'  # RGB(229, 192, 123)
RED=$'\e[38;2;224;108;117m'     # RGB(224, 108, 117)
GRAY=$'\e[38;2;74;88;92m'       # RGB(74, 88, 92)
```

## トラブルシューティング

### レートリミットが `--％` と表示される

- OAuth 認証でログインしているか確認してください（API キー認証では動作しません）
- `security find-generic-password -s "Claude Code-credentials" -w` でトークンが取得できるか確認してください
- キャッシュを削除して再取得: `rm /tmp/claude-usage-cache.json`

### git ブランチが表示されない

作業ディレクトリが git リポジトリ内でない場合は表示されません。これは正常な動作です。

### 変更行数が表示されない

セッション開始直後は変更行数が 0 のため表示されません。コードを編集すると自動的に表示されます。

## License

MIT
