# Claude Code Statusline

Claude Code のステータスラインに、モデル情報・コンテキスト使用率・セッションコストをリアルタイム表示するシェルスクリプトです。

詳しい解説は Zenn 記事をご覧ください：
**[Claude Codeのステータスラインに使用率を出す](https://zenn.dev/suthio/articles/f832922e18f994)**

## 2つのバージョン

| スクリプト | 表示内容 | API 呼び出し | ToS リスク |
|-----------|----------|-------------|-----------|
| `statusline-command.sh` | コンテキスト使用率 + セッションコスト | なし（stdin のみ） | なし |
| `statusline-command-with-usage.sh` | 5h/7d レートリミット使用率 | あり（Haiku probe） | **あり** |

### statusline-command.sh（推奨）

```
🤖 Opus 4.6 │ 📊 48% │ ✏️  +162/-34 │ 🔀 main
📐 CTX  ▰▰▰▰▰▱▱▱▱▱  48%  96K / 200K tokens
💰 $4.23
```

Claude Code が stdin で提供するデータのみを使用します。外部 API 呼び出しやキーチェーンアクセスは一切行いません。

### statusline-command-with-usage.sh

```
🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
```

5時間 / 7日間のレートリミット使用率をリアルタイム表示します。リセット時刻も併記されるため、いつ制限が解除されるかが一目でわかります。

> **⚠️ 利用規約に関する注意**
>
> このスクリプトは macOS キーチェーンから OAuth トークンを取得し、Anthropic API に直接リクエスト（Haiku probe）を送信してレートリミット情報を取得します。
>
> [Anthropic Consumer Terms of Service §3(7)](https://www.anthropic.com/legal/consumer-terms) では以下のように規定されています：
>
> > *"You may not [...] access the Services through automated means (e.g., scripts) using credentials other than API Keys."*
>
> Claude Code のキーチェーンから取得した OAuth トークンをスクリプトから使用することは、この条項に抵触する可能性があります。**利用は自己責任でお願いします。**

## 表示内容

### 1行目：セッション情報

| 項目 | 説明 |
|------|------|
| 🤖 モデル名 | 使用中のモデル（Opus 4.6, Sonnet 4.5 等） |
| 📊 コンテキスト使用率 | コンテキストウィンドウの消費率（200K トークン中） |
| ✏️ 変更行数 | セッション内の累計 `+追加/-削除` 行数 |
| 🔀 ブランチ名 | 作業ディレクトリの git ブランチ（git リポジトリ内のみ表示） |

### 2行目（推奨版）：コンテキストウィンドウ詳細

使用率をプログレスバー（▰▱ × 10セグメント）で表示し、使用トークン数 / 総トークン数を併記します。

### 2行目（Usage 版）：5時間レートリミット

5時間ウィンドウの使用率をプログレスバーで表示します。リセット時刻を Asia/Tokyo タイムゾーンで併記します。

### 3行目（推奨版）：セッションコスト

セッションの累計 API 費用を $X.XX 形式で表示します。

### 3行目（Usage 版）：7日間レートリミット

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

**推奨版（ToS 準拠）：**

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
```

**Usage 版（レートリミット表示、ToS リスクあり）：**

```bash
cp statusline-command-with-usage.sh ~/.claude/statusline-command.sh
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

### 共通

| 要件 | 用途 |
|------|------|
| `jq` | JSON パース |
| `git` | ブランチ名取得 |

### Usage 版のみ（追加要件）

| 要件 | 用途 |
|------|------|
| macOS | `security` コマンドでキーチェーンから OAuth トークンを取得 |
| `curl` | API 呼び出し |
| Claude Code の OAuth 認証 | API キー認証ではなく OAuth ログインが必要 |

`jq` が未インストールの場合：

```bash
brew install jq
```

## アーキテクチャ

### データソース

#### stdin（Claude Code が自動提供）

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

推奨版はこの stdin のみを使用します。

#### Haiku プローブ（Usage 版のみ）

Usage 版は追加で Anthropic API のレスポンスヘッダーからレートリミット情報を取得します。Haiku に `max_tokens: 1` の最小リクエストを送信し、以下のヘッダーを読み取ります：

```
anthropic-ratelimit-unified-5h-utilization: 0.28
anthropic-ratelimit-unified-5h-reset: 1772791200
anthropic-ratelimit-unified-7d-utilization: 0.59
anthropic-ratelimit-unified-7d-reset: 1772784000
```

> **なぜ `/api/oauth/usage` を使わないのか？**
>
> Anthropic は `/api/oauth/usage` という REST エンドポイントも提供していますが、アカウントのレートリミットに達している状態ではこのエンドポイント自体が 429 を返します。つまり、使用率を最も確認したいタイミングで使えません。Haiku プローブ方式なら、アカウントがレートリミット中でもレスポンスヘッダーにリミット情報が含まれるため、確実に取得できます。

### キャッシュ（Usage 版のみ）

- キャッシュファイル: `/tmp/claude-usage-cache.json`
- キャッシュ TTL: 360秒（6分）
- API 失敗時は古いキャッシュをフォールバック使用
- 1プローブあたりのコスト: 約 $0.00001（Haiku 1トークン）

## カスタマイズ

### キャッシュ TTL を変更する（Usage 版）

スクリプト内の `CACHE_TTL=360` を変更してください（単位: 秒）。値を小さくするとより頻繁に API を呼びますが、Haiku のコストは極めて低いため実用上問題ありません。

### タイムゾーンを変更する（Usage 版）

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

### レートリミットが `--％` と表示される（Usage 版）

- OAuth 認証でログインしているか確認してください（API キー認証では動作しません）
- `security find-generic-password -s "Claude Code-credentials" -w` でトークンが取得できるか確認してください
- キャッシュを削除して再取得: `rm /tmp/claude-usage-cache.json`

### git ブランチが表示されない

作業ディレクトリが git リポジトリ内でない場合は表示されません。これは正常な動作です。

### 変更行数が表示されない

セッション開始直後は変更行数が 0 のため表示されません。コードを編集すると自動的に表示されます。

## License

MIT
