#!/usr/bin/env bash
set -euo pipefail

# 中文：为 Railway 分离部署提供可重复执行的服务创建与配置入口。
# English: Provide a repeatable service creation and configuration entrypoint for split Railway deployments.

RAILWAY_BIN="${RAILWAY_BIN:-railway}"
PROJECT_ID="${RAILWAY_PROJECT_ID:?Set RAILWAY_PROJECT_ID to the target Railway project ID.}"
ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"
BRANCH="${RAILWAY_BRANCH:-codex/langflow-python-railway}"
API_SERVICE="${RAILWAY_API_SERVICE:-langflow-api}"
WEB_SERVICE="${RAILWAY_WEB_SERVICE:-langflow-web}"
POSTGRES_SERVICE="${RAILWAY_POSTGRES_SERVICE:-Postgres}"
REDIS_SERVICE="${RAILWAY_REDIS_SERVICE:-Redis}"
DEPLOY="${RAILWAY_DEPLOY:-false}"

service_exists() {
  local service_name="$1"
  local services_json
  if ! services_json="$("$RAILWAY_BIN" service list \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --json)"; then
    printf 'Failed to list Railway services for %s/%s.\n' "$PROJECT_ID" "$ENVIRONMENT" >&2
    exit 1
  fi

  set +e
  python3 - "$service_name" "$services_json" <<'PY'
import json
import sys

target = sys.argv[1]
try:
    services = json.loads(sys.argv[2])
except json.JSONDecodeError:
    sys.exit(2)

sys.exit(0 if any(service.get("name") == target for service in services) else 1)
PY
  local status="$?"
  set -e

  if [[ "$status" == "0" ]]; then
    return 0
  fi

  if [[ "$status" == "1" ]]; then
    return 1
  fi

  printf 'Failed to parse Railway service list JSON.\n' >&2
  exit "$status"
}

ensure_database() {
  local database_type="$1"
  local service_name="$2"
  if service_exists "$service_name"; then
    printf 'Using existing %s service: %s\n' "$database_type" "$service_name"
    return
  fi

  local output
  output="$("$RAILWAY_BIN" add --database "$database_type" --json)"
  local created_name
  created_name="$(
    python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(payload.get("serviceName", ""))
PY
  )"

  # 中文：阻止数据库服务名不匹配时继续写入错误的跨服务变量引用。
  # English: Prevent writing broken cross-service variable references when the database service name differs.
  if [[ "$created_name" != "$service_name" ]]; then
    printf 'Created %s service with unexpected name: %s\n' "$database_type" "${created_name:-<empty>}" >&2
    printf 'Expected service name: %s\n' "$service_name" >&2
    exit 1
  fi

  printf 'Created %s service: %s\n' "$database_type" "$created_name"
}

if service_exists "$POSTGRES_SERVICE"; then
  "$RAILWAY_BIN" link \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$POSTGRES_SERVICE" \
    --json >/dev/null
else
  "$RAILWAY_BIN" link \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --json >/dev/null
fi

ensure_database postgres "$POSTGRES_SERVICE"
ensure_database redis "$REDIS_SERVICE"

for service_name in "$API_SERVICE" "$WEB_SERVICE"; do
  if service_exists "$service_name"; then
    printf 'Using existing service: %s\n' "$service_name"
  else
    "$RAILWAY_BIN" add --service "$service_name" --json >/dev/null
    printf 'Created service: %s\n' "$service_name"
  fi
done

"$RAILWAY_BIN" environment edit \
  --project "$PROJECT_ID" \
  --environment "$ENVIRONMENT" \
  --service-config "$API_SERVICE" source.repo "NSNanoCat/langflow" \
  --service-config "$API_SERVICE" source.branch "$BRANCH" \
  --service-config "$API_SERVICE" build.builder DOCKERFILE \
  --service-config "$API_SERVICE" build.dockerfilePath "docker/build_and_push_backend.Dockerfile" \
  --service-config "$API_SERVICE" deploy.healthcheckPath "/health" \
  --service-config "$WEB_SERVICE" source.repo "NSNanoCat/langflow" \
  --service-config "$WEB_SERVICE" source.branch "$BRANCH" \
  --service-config "$WEB_SERVICE" build.builder DOCKERFILE \
  --service-config "$WEB_SERVICE" build.dockerfilePath "docker/frontend/build_and_push_frontend.Dockerfile" \
  --service-config "$WEB_SERVICE" deploy.healthcheckPath "/health" \
  --json >/dev/null

"$RAILWAY_BIN" variable set \
  --project "$PROJECT_ID" \
  --environment "$ENVIRONMENT" \
  --service "$API_SERVICE" \
  --skip-deploys \
  "LANGFLOW_BACKEND_ONLY=True" \
  "LANGFLOW_HOST=::" \
  "LANGFLOW_PORT=7860" \
  "LANGFLOW_DATABASE_URL=\${{${POSTGRES_SERVICE}.DATABASE_URL}}" \
  "LANGFLOW_ALEMBIC_LOG_TO_STDOUT=True" \
  "LANGFLOW_AUTO_LOGIN=False" \
  "LANGFLOW_CACHE_TYPE=redis" \
  "LANGFLOW_REDIS_URL=\${{${REDIS_SERVICE}.REDIS_URL}}" \
  --json >/dev/null

"$RAILWAY_BIN" variable set \
  --project "$PROJECT_ID" \
  --environment "$ENVIRONMENT" \
  --service "$WEB_SERVICE" \
  --skip-deploys \
  "BACKEND_URL=http://\${{${API_SERVICE}.RAILWAY_PRIVATE_DOMAIN}}:7860" \
  --json >/dev/null

"$RAILWAY_BIN" domain \
  --project "$PROJECT_ID" \
  --environment "$ENVIRONMENT" \
  --service "$WEB_SERVICE" \
  --port 80 \
  --json >/dev/null || true

if [[ "$DEPLOY" == "true" ]]; then
  "$RAILWAY_BIN" up \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$API_SERVICE" \
    --detach \
    --message "Deploy split Langflow API"

  "$RAILWAY_BIN" up \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$WEB_SERVICE" \
    --detach \
    --message "Deploy split Langflow web"
fi

printf 'Railway split Langflow services are configured for %s/%s.\n' "$PROJECT_ID" "$ENVIRONMENT"
