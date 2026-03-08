# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code のステータスラインに3行表示するための bash スクリプト。`~/.claude/settings.json` の `statusLine.command` から呼ばれる。2つのバージョンがある。

## Scripts

| ファイル | 説明 |
|---------|------|
| `statusline-command.sh` | 推奨版。stdin のみ使用、API 呼び出しなし |
| `statusline-command-with-usage.sh` | Usage 版。Haiku probe で 5h/7d レートリミット表示（ToS リスクあり） |

## Architecture

### statusline-command.sh（推奨版）

```
Claude Code → stdin (JSON) → statusline-command.sh → stdout (3-line ANSI text)
```

stdin のみをデータソースとし、外部 API 呼び出し・キーチェーンアクセスは一切行わない。

### statusline-command-with-usage.sh（Usage 版）

```
Claude Code → stdin (JSON) → statusline-command-with-usage.sh → stdout (3-line ANSI text)
                                         ↓
                               Haiku probe (curl) → response headers → /tmp/claude-usage-cache.json
```

Haiku への最小 API 呼び出し（`max_tokens:1`）でレスポンスヘッダー `anthropic-ratelimit-unified-{5h,7d}-{utilization,reset}` を解析する。キャッシュ TTL 360秒。

## Testing

```bash
# 推奨版のテスト
echo '{"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":50,"context_window_size":200000},"cwd":".","cost":{"total_cost_usd":4.23,"total_lines_added":10,"total_lines_removed":3},"version":"2.1.69"}' | bash statusline-command.sh

# ANSI エスケープを可視化
echo '...' | bash statusline-command.sh | cat -v

# Usage 版のテスト（キャッシュクリア）
rm -f /tmp/claude-usage-cache.json
echo '...' | bash statusline-command-with-usage.sh
```

## Key Constraints

### 共通
- `printf '%s\n'` で出力すること（`printf "$var\n"` は `%` を誤解釈する）
- ANSI カラーは `$'\e[...]'` 形式で定義すること（`'\033[...]'` リテラルだと `printf '%s'` で展開されない）
- `eval "$(jq ...)"` 禁止（コマンドインジェクションリスク）。`jq -r` の結果を変数に直接代入する

### Usage 版のみ
- macOS 専用（`security` コマンド、`date -j -f`、`stat -f '%m'`）
- OAuth 認証必須（API キー認証では Haiku probe が動作しない）
- Anthropic Consumer Terms §3(7) に抵触する可能性あり
