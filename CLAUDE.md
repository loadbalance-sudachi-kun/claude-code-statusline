# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code のステータスラインに3行表示するための bash スクリプト（単一ファイル）。`~/.claude/settings.json` の `statusLine.command` から呼ばれる。

## Architecture

`statusline-command.sh` がすべて。stdin から Claude Code が渡す JSON を受け取り、ANSI カラー付きの3行テキストを stdout に出力する。

### Data Flow

```
Claude Code → stdin (JSON) → statusline-command.sh → stdout (3-line ANSI text)
                                    ↓
                          Haiku probe (curl) → response headers → /tmp/claude-usage-cache.json
```

### stdin JSON (Claude Code が提供)

`model.display_name`, `context_window.used_percentage`, `cost.total_lines_added`, `cost.total_lines_removed`, `cwd`, `version` を使用。レートリミット情報は stdin に含まれない。

### Haiku Probe (レートリミット取得)

`/api/oauth/usage` はレートリミット到達時に 429 を返すため使用不可。代わりに Haiku への最小 API 呼び出し（`max_tokens:1`）を行い、レスポンスヘッダー `anthropic-ratelimit-unified-{5h,7d}-{utilization,reset}` を解析する。`anthropic-beta: oauth-2025-04-20` ヘッダーが必須（OAuth トークンで Messages API を使うため）。

### Cache

`/tmp/claude-usage-cache.json` に 360 秒 TTL でキャッシュ。API 失敗時は古いキャッシュをフォールバック。

## Testing

単一の bash スクリプトのため自動テストはない。手動テスト:

```bash
# stdin JSON を渡してテスト（実際のキーチェーントークンを使用）
echo '{"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":50},"cwd":".","cost":{"total_lines_added":10,"total_lines_removed":3},"version":"2.1.69"}' | bash statusline-command.sh

# ANSI エスケープを可視化して確認
echo '...' | bash statusline-command.sh | cat -v

# キャッシュを消して API 呼び出しを強制
rm /tmp/claude-usage-cache.json
```

## Key Constraints

- macOS 専用（`security` コマンド、`date -j -f`、`stat -f '%m'`）
- OAuth 認証必須（API キー認証では Haiku probe が動作しない）
- `printf '%s\n'` で出力すること（`printf "$var\n"` は `%` を誤解釈する）
- ANSI カラーは `$'\e[...]'` 形式で定義すること（`'\033[...]'` リテラルだと `printf '%s'` で展開されない）
- リセット時刻は epoch 秒で返るため ISO8601 変換不要
