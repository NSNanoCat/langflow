#!/usr/bin/env bash
set -euo pipefail

# 中文：从已验证的 Railway 项目生成 Langflow 分离部署模板草稿，并可显式发布已有模板。
# English: Generate a Langflow split deployment template draft from a verified Railway project and optionally publish an existing template.

RAILWAY_BIN="${RAILWAY_BIN:-railway}"
STATE_FILE="${RAILWAY_STATE_FILE:-./railway-langflow-template.env}"

if [[ -f "$STATE_FILE" ]]; then
  # 中文：复用 setup 脚本写出的项目与环境信息，减少模板命令的手工参数。
  # English: Reuse project and environment data written by the setup script to reduce manual template command arguments.
  set -a
  source "$STATE_FILE"
  set +a
fi

PROJECT_ID="${RAILWAY_PROJECT_ID:-}"
ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"
PUBLISH_TEMPLATE="${RAILWAY_TEMPLATE_PUBLISH:-false}"
TEMPLATE_ID="${RAILWAY_TEMPLATE_ID:-}"
if [[ -n "${RAILWAY_TEMPLATE_CREATE:-}" ]]; then
  CREATE_TEMPLATE="$RAILWAY_TEMPLATE_CREATE"
elif [[ -n "$TEMPLATE_ID" ]]; then
  CREATE_TEMPLATE="false"
else
  CREATE_TEMPLATE="true"
fi
TEMPLATE_CATEGORY="${RAILWAY_TEMPLATE_CATEGORY:-AI/ML}"
TEMPLATE_DESCRIPTION="${RAILWAY_TEMPLATE_DESCRIPTION:-Deploy split Langflow with Postgres and Redis}"
TEMPLATE_README_FILE="${RAILWAY_TEMPLATE_README_FILE:-scripts/railway/template-readme.md}"
TEMPLATE_OUTPUT_FILE="${RAILWAY_TEMPLATE_OUTPUT_FILE:-./railway-langflow-template.json}"

if [[ -z "$PROJECT_ID" ]]; then
  printf 'Set RAILWAY_PROJECT_ID or provide RAILWAY_STATE_FILE from setup-langflow-split.sh.\n' >&2
  exit 1
fi

if [[ "$CREATE_TEMPLATE" == "true" ]]; then
  output="$("$RAILWAY_BIN" templates create \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --json)"
  printf '%s\n' "$output" >"$TEMPLATE_OUTPUT_FILE"

  TEMPLATE_ID="$(
    python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
candidates = [
    payload.get("id"),
    (payload.get("template") or {}).get("id"),
    (payload.get("templateCreate") or {}).get("id"),
    ((payload.get("data") or {}).get("template") or {}).get("id"),
    ((payload.get("data") or {}).get("templateCreate") or {}).get("id"),
]
for candidate in candidates:
    if candidate:
        print(candidate)
        raise SystemExit(0)
raise SystemExit(1)
PY
  )"

  if [[ -n "$STATE_FILE" ]]; then
    tmp_file="$(mktemp)"
    if [[ -f "$STATE_FILE" ]]; then
      awk -v value="$TEMPLATE_ID" '
        BEGIN { written = 0 }
        /^RAILWAY_TEMPLATE_ID=/ {
          print "RAILWAY_TEMPLATE_ID=" value
          written = 1
          next
        }
        { print }
        END {
          if (!written) {
            print "RAILWAY_TEMPLATE_ID=" value
          }
        }
      ' "$STATE_FILE" >"$tmp_file"
    else
      printf 'RAILWAY_TEMPLATE_ID=%s\n' "$TEMPLATE_ID" >"$tmp_file"
    fi
    mv "$tmp_file" "$STATE_FILE"
  fi

  printf 'Created Railway template draft: %s\n' "$TEMPLATE_ID"
  printf 'Wrote template JSON: %s\n' "$TEMPLATE_OUTPUT_FILE"
fi

if [[ "$PUBLISH_TEMPLATE" != "true" ]]; then
  printf 'Review template variables in Railway before publishing. Set RAILWAY_TEMPLATE_PUBLISH=true to publish.\n'
  exit 0
fi

if [[ -z "$TEMPLATE_ID" ]]; then
  printf 'Set RAILWAY_TEMPLATE_ID or create a template draft first.\n' >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_README_FILE" ]]; then
  printf 'Template README file not found: %s\n' "$TEMPLATE_README_FILE" >&2
  exit 1
fi

# 中文：发布只更新模板市场元数据；发布前仍需在 Railway 模板编辑器中把固定密钥替换为 secret 变量。
# English: Publishing only updates marketplace metadata; replace fixed secrets with secret variables in the Railway template editor first.
"$RAILWAY_BIN" templates publish "$TEMPLATE_ID" \
  --category "$TEMPLATE_CATEGORY" \
  --description "$TEMPLATE_DESCRIPTION" \
  --readme-file "$TEMPLATE_README_FILE" \
  --json
