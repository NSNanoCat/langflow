#!/usr/bin/env bash
set -euo pipefail

# 中文：为 Railway 分离部署提供可重复执行的服务创建、重置与配置入口。
# English: Provide a repeatable service creation, reset, and configuration entrypoint for split Railway deployments.

RAILWAY_BIN="${RAILWAY_BIN:-railway}"
PROJECT_ID="${RAILWAY_PROJECT_ID:-}"
PROJECT_NAME="${RAILWAY_PROJECT_NAME:-}"
WORKSPACE="${RAILWAY_WORKSPACE:-}"
ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"
BRANCH="${RAILWAY_BRANCH:-codex/langflow-python-railway}"
REPO="${RAILWAY_REPO:-NSNanoCat/langflow}"
API_SERVICE="${RAILWAY_API_SERVICE:-langflow-api}"
WEB_SERVICE="${RAILWAY_WEB_SERVICE:-langflow-web}"
POSTGRES_SERVICE="${RAILWAY_POSTGRES_SERVICE:-Postgres}"
REDIS_SERVICE="${RAILWAY_REDIS_SERVICE:-Redis}"
DEPLOY="${RAILWAY_DEPLOY:-false}"
RESET="${RAILWAY_RESET:-false}"
CREATE_DOMAIN="${RAILWAY_CREATE_DOMAIN:-true}"
GRAPHQL_ENDPOINT="${RAILWAY_GRAPHQL_ENDPOINT:-https://backboard.railway.com/graphql/v2}"
STATE_FILE="${RAILWAY_STATE_FILE:-}"

require_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required.\n' >&2
    exit 1
  fi
}

railway_token() {
  local config_file="${RAILWAY_CONFIG_FILE:-$HOME/.railway/config.json}"
  if [[ ! -f "$config_file" ]]; then
    return 1
  fi

  python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    config = json.load(file)

user = config.get("user") or {}
print(user.get("token") or user.get("accessToken") or "")
PY
}

graphql_request() {
  local query="$1"
  local variables="$2"
  local token
  if ! token="$(railway_token)"; then
    return 1
  fi

  if [[ -z "$token" ]]; then
    return 1
  fi

  local payload
  payload="$(
    python3 - "$query" "$variables" <<'PY'
import json
import sys

print(json.dumps({"query": sys.argv[1], "variables": json.loads(sys.argv[2])}))
PY
  )"

  local output
  if ! output="$(curl -fsS "$GRAPHQL_ENDPOINT" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -H "X-Railway-Skill-Id: use-railway" \
    -H "X-Railway-Skill-Version: 1.2.2" \
    -H "X-Railway-Agent-Session: railway-skill-langflow-split-setup" \
    -d "$payload")"; then
    return 1
  fi

  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if payload.get("errors"):
    sys.exit(1)
print(json.dumps(payload.get("data") or {}))
PY
}

read_json_value() {
  local payload="$1"
  local path="$2"
  python3 - "$payload" "$path" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload
for part in sys.argv[2].split("."):
    value = value.get(part, "") if isinstance(value, dict) else ""
print(value if value is not None else "")
PY
}

environment_id() {
  local output
  output="$("$RAILWAY_BIN" environment list --json)"
  python3 - "$ENVIRONMENT" "$output" <<'PY'
import json
import sys

target = sys.argv[1]
environments = json.loads(sys.argv[2])
if isinstance(environments, dict):
    environments = [
        edge.get("node", {})
        for edge in (environments.get("environments", {}) or {}).get("edges", [])
    ]
for environment in environments:
    if environment.get("name") == target or environment.get("id") == target:
        print(environment.get("id", ""))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

service_has_repo_source() {
  local service_name="$1"
  local services_json
  services_json="$("$RAILWAY_BIN" service list \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --json)"

  python3 - "$service_name" "$REPO" "$services_json" <<'PY'
import json
import sys

target, repo = sys.argv[1], sys.argv[2]
services = json.loads(sys.argv[3])
for service in services:
    if service.get("name") != target:
        continue
    source = service.get("source") or {}
    raise SystemExit(0 if source.get("repo") == repo else 1)
raise SystemExit(1)
PY
}

create_project_if_needed() {
  if [[ -n "$PROJECT_ID" ]]; then
    return
  fi

  if [[ -z "$PROJECT_NAME" ]]; then
    printf 'Set RAILWAY_PROJECT_ID for an existing project or RAILWAY_PROJECT_NAME to create one.\n' >&2
    exit 1
  fi

  local args=(init --name "$PROJECT_NAME" --json)
  if [[ -n "$WORKSPACE" ]]; then
    args+=(--workspace "$WORKSPACE")
  fi

  local output
  output="$("$RAILWAY_BIN" "${args[@]}")"
  PROJECT_ID="$(read_json_value "$output" id)"

  if [[ -z "$PROJECT_ID" ]]; then
    printf 'Failed to create Railway project from CLI output.\n' >&2
    exit 1
  fi

  printf 'Created Railway project: %s (%s)\n' "$PROJECT_NAME" "$PROJECT_ID"
}

link_project() {
  "$RAILWAY_BIN" link \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --json >/dev/null
}

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

reset_service_if_requested() {
  local service_name="$1"
  if [[ "$RESET" != "true" ]]; then
    return
  fi

  if ! service_exists "$service_name"; then
    return
  fi

  # 中文：仅在显式 RAILWAY_RESET=true 时删除目标服务，避免误删已有数据服务。
  # English: Delete target services only with explicit RAILWAY_RESET=true to avoid accidental data loss.
  "$RAILWAY_BIN" service delete \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$service_name" \
    --yes \
    --json >/dev/null
  printf 'Deleted service for reset: %s\n' "$service_name"
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
  created_name="$(read_json_value "$output" serviceName)"

  # 中文：阻止数据库服务名不匹配时继续写入错误的跨服务变量引用。
  # English: Prevent writing broken cross-service variable references when the database service name differs.
  if [[ "$created_name" != "$service_name" ]]; then
    printf 'Created %s service with unexpected name: %s\n' "$database_type" "${created_name:-<empty>}" >&2
    printf 'Expected service name: %s\n' "$service_name" >&2
    exit 1
  fi

  printf 'Created %s service: %s\n' "$database_type" "$created_name"
}

ensure_app_service() {
  local service_name="$1"
  if service_exists "$service_name"; then
    printf 'Using existing service: %s\n' "$service_name"
    return
  fi

  local env_id
  env_id="$(environment_id)"
  local variables
  variables="$(
    python3 - "$PROJECT_ID" "$env_id" "$service_name" "$REPO" "$BRANCH" <<'PY'
import json
import sys

print(json.dumps({
    "input": {
        "projectId": sys.argv[1],
        "environmentId": sys.argv[2],
        "name": sys.argv[3],
        "source": {"repo": sys.argv[4]},
        "branch": sys.argv[5],
    }
}))
PY
  )"
  local query='mutation createService($input: ServiceCreateInput!) { serviceCreate(input: $input) { id name } }'

  # 中文：优先通过 GraphQL 创建带 GitHub source 的服务，避免 CLI 空服务后补 source 在部分环境中不生效。
  # English: Prefer GraphQL repo-backed service creation because patching source onto empty CLI services can fail in some environments.
  if graphql_request "$query" "$variables" >/dev/null; then
    printf 'Created repo-backed service: %s\n' "$service_name"
    return
  fi

  # 中文：GraphQL token 不可用时回退为空服务，后续 environment edit 仍会尝试写入 source。
  # English: Fall back to an empty service when the GraphQL token is unavailable; environment edit will still try to set source.
  "$RAILWAY_BIN" add --service "$service_name" --json >/dev/null
  printf 'Created service: %s\n' "$service_name"
}

generate_secret_key() {
  python3 - <<'PY'
import base64
import os

print(base64.urlsafe_b64encode(os.urandom(32)).decode())
PY
}

generate_password() {
  python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits + "-_"
print("".join(secrets.choice(alphabet) for _ in range(32)))
PY
}

configure_services() {
  "$RAILWAY_BIN" environment edit \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service-config "$API_SERVICE" source.repo "$REPO" \
    --service-config "$API_SERVICE" source.branch "$BRANCH" \
    --service-config "$API_SERVICE" build.builder DOCKERFILE \
    --service-config "$API_SERVICE" build.dockerfilePath "docker/build_and_push_backend.Dockerfile" \
    --service-config "$API_SERVICE" deploy.healthcheckPath "/health_check" \
    --service-config "$WEB_SERVICE" source.repo "$REPO" \
    --service-config "$WEB_SERVICE" source.branch "$BRANCH" \
    --service-config "$WEB_SERVICE" build.builder DOCKERFILE \
    --service-config "$WEB_SERVICE" build.dockerfilePath "docker/frontend/build_and_push_frontend.Dockerfile" \
    --service-config "$WEB_SERVICE" deploy.healthcheckPath "/health" \
    --json >/dev/null

  # 中文：如果 Railway 未接受 source 配置，立即失败，避免生成不可部署的模板源项目。
  # English: Fail fast when Railway does not accept source configuration to avoid creating an undeployable template source project.
  if ! service_has_repo_source "$API_SERVICE" || ! service_has_repo_source "$WEB_SERVICE"; then
    printf 'Railway did not attach repo source to %s/%s. Run `railway login` and retry.\n' "$API_SERVICE" "$WEB_SERVICE" >&2
    exit 1
  fi
}

configure_variables() {
  local superuser="${LANGFLOW_SUPERUSER:-admin}"
  local superuser_password="${LANGFLOW_SUPERUSER_PASSWORD:-}"
  local secret_key="${LANGFLOW_SECRET_KEY:-}"

  if [[ -z "$superuser_password" ]]; then
    superuser_password="$(generate_password)"
    printf 'Generated LANGFLOW_SUPERUSER_PASSWORD for %s.\n' "$API_SERVICE"
  fi

  if [[ -z "$secret_key" ]]; then
    secret_key="$(generate_secret_key)"
    printf 'Generated Fernet-compatible LANGFLOW_SECRET_KEY for %s.\n' "$API_SERVICE"
  fi

  "$RAILWAY_BIN" variable set \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$API_SERVICE" \
    --skip-deploys \
    "LANGFLOW_BACKEND_ONLY=True" \
    "LANGFLOW_HOST=0.0.0.0" \
    "PORT=7860" \
    "LANGFLOW_PORT=7860" \
    "LANGFLOW_DATABASE_URL=\${{${POSTGRES_SERVICE}.DATABASE_URL}}" \
    "LANGFLOW_ALEMBIC_LOG_TO_STDOUT=True" \
    "LANGFLOW_AUTO_LOGIN=False" \
    "LANGFLOW_SUPERUSER=${superuser}" \
    "LANGFLOW_SUPERUSER_PASSWORD=${superuser_password}" \
    "LANGFLOW_SECRET_KEY=${secret_key}" \
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
}

create_domain() {
  if [[ "$CREATE_DOMAIN" != "true" ]]; then
    return
  fi

  "$RAILWAY_BIN" domain \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$WEB_SERVICE" \
    --port 80 \
    --json >/dev/null || true
}

deploy_services() {
  if [[ "$DEPLOY" != "true" ]]; then
    return
  fi

  "$RAILWAY_BIN" redeploy \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$API_SERVICE" \
    --from-source \
    --yes \
    --json >/dev/null

  "$RAILWAY_BIN" redeploy \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$WEB_SERVICE" \
    --from-source \
    --yes \
    --json >/dev/null
}

write_state_file() {
  if [[ -z "$STATE_FILE" ]]; then
    return
  fi

  # 中文：写出后续模板创建命令需要的项目与环境信息，避免新建项目 ID 只存在于子进程内。
  # English: Write project and environment data needed by later template commands so new project IDs do not stay trapped in the subprocess.
  cat >"$STATE_FILE" <<EOF
RAILWAY_PROJECT_ID=${PROJECT_ID}
RAILWAY_ENVIRONMENT=${ENVIRONMENT}
RAILWAY_API_SERVICE=${API_SERVICE}
RAILWAY_WEB_SERVICE=${WEB_SERVICE}
RAILWAY_POSTGRES_SERVICE=${POSTGRES_SERVICE}
RAILWAY_REDIS_SERVICE=${REDIS_SERVICE}
EOF
}

main() {
  require_python
  create_project_if_needed
  link_project

  reset_service_if_requested "$WEB_SERVICE"
  reset_service_if_requested "$API_SERVICE"
  reset_service_if_requested "$REDIS_SERVICE"
  reset_service_if_requested "$POSTGRES_SERVICE"

  ensure_database postgres "$POSTGRES_SERVICE"
  ensure_database redis "$REDIS_SERVICE"
  ensure_app_service "$API_SERVICE"
  ensure_app_service "$WEB_SERVICE"
  configure_services
  configure_variables
  create_domain
  deploy_services
  write_state_file

  printf 'Railway split Langflow services are configured for %s/%s.\n' "$PROJECT_ID" "$ENVIRONMENT"
}

main "$@"
