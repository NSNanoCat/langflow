# Railway split deployment

This directory contains repeatable setup helpers for a Railway project with separate Langflow API and web services.

## Services

The setup script configures:

- `langflow-api`: backend-only Langflow API from `docker/build_and_push_backend.Dockerfile`
- `langflow-web`: static frontend from `docker/frontend/build_and_push_frontend.Dockerfile`
- `Postgres`: Railway-managed PostgreSQL
- `Redis`: Railway-managed Redis for the experimental Langflow cache backend

## Usage

```bash
export PATH="$HOME/.railway/bin:$PATH"
export RAILWAY_PROJECT_ID="c4fdba9b-5085-415e-a0da-7cbd079defa5"
export RAILWAY_BRANCH="codex/langflow-python-railway"
scripts/railway/setup-langflow-split.sh
```

To deploy after configuration:

```bash
RAILWAY_DEPLOY=true scripts/railway/setup-langflow-split.sh
```

The script is idempotent for the expected service names: it reuses existing services and creates missing ones.
It does not delete services or reset database data.
If Railway creates a database service with a different name than expected, the script stops so variable references do not point at a missing service.
Push the configured branch before deploying from Railway GitHub sources.
`langflow-api` is pinned to `LANGFLOW_HOST=0.0.0.0` and `LANGFLOW_PORT=7860`, and `langflow-web` proxies to that private Railway endpoint.

## Required secrets

After setup, set these on `langflow-api` if they are not already present:

```text
LANGFLOW_SUPERUSER=<admin-user>
LANGFLOW_SUPERUSER_PASSWORD=<admin-password>
LANGFLOW_SECRET_KEY=<generated-secret>
```

For a Railway Template, create a template from the configured project in the Railway dashboard and use template variable functions such as `${{secret()}}` for `LANGFLOW_SUPERUSER_PASSWORD` and `LANGFLOW_SECRET_KEY`.
