# Railway split deployment

This directory contains repeatable setup helpers for a Railway project with separate Langflow API and web services.

## Services

The setup script configures:

- `langflow-api`: backend-only Langflow API from `docker/build_and_push_backend.Dockerfile`
- `langflow-web`: static frontend from `docker/frontend/build_and_push_frontend.Dockerfile`
- `Postgres`: Railway-managed PostgreSQL
- `Redis`: Railway-managed Redis for the experimental Langflow cache backend

## Usage

Configure an existing project:

```bash
export PATH="$HOME/.railway/bin:$PATH"
export RAILWAY_PROJECT_ID="<project-id>"
export RAILWAY_BRANCH="<branch-name>"
scripts/railway/setup-langflow-split.sh
```

Create a new project from scratch:

```bash
export PATH="$HOME/.railway/bin:$PATH"
export RAILWAY_PROJECT_NAME="Langflow Split"
export RAILWAY_WORKSPACE="<workspace-id-or-name>"
export RAILWAY_BRANCH="<branch-name>"
export RAILWAY_STATE_FILE="./railway-langflow-split.env"
scripts/railway/setup-langflow-split.sh
```

To deploy after configuration:

```bash
RAILWAY_DEPLOY=true scripts/railway/setup-langflow-split.sh
```

To reset only the managed split services in the target project, set `RAILWAY_RESET=true`.
This deletes and recreates `langflow-api`, `langflow-web`, `Postgres`, and `Redis`; it does not touch differently named services.

The script is idempotent for the expected service names: it reuses existing services and creates missing ones.
It does not delete services or reset database data unless `RAILWAY_RESET=true` is set.
If Railway creates a database service with a different name than expected, the script stops so variable references do not point at a missing service.
Push the configured branch before deploying from Railway GitHub sources.
`langflow-api` is pinned to `LANGFLOW_HOST=0.0.0.0`, `PORT=7860`, and `LANGFLOW_PORT=7860`; `langflow-web` proxies to that private Railway endpoint.
The web service health check targets its local `/health` endpoint; verify API proxy connectivity separately with `/health_check`.
`langflow-web` configures nginx with the container DNS resolver so the proxy follows Railway private-network address changes after API redeploys.

## Required secrets

After setup, set these on `langflow-api` if they are not already present:

```text
LANGFLOW_SUPERUSER=<admin-user>
LANGFLOW_SUPERUSER_PASSWORD=<admin-password>
LANGFLOW_SECRET_KEY=<generated-secret>
```

If `LANGFLOW_SUPERUSER_PASSWORD` or `LANGFLOW_SECRET_KEY` are not set before running the script, it generates values for the target `langflow-api` service.
`LANGFLOW_SECRET_KEY` is generated as a Fernet-compatible key to avoid starter MCP server encryption failures.

## Template draft

Create a clean project with only the four split services, verify it, then generate a template draft:

```bash
export RAILWAY_PROJECT_NAME="Langflow Split Template"
export RAILWAY_WORKSPACE="<workspace-id-or-name>"
export RAILWAY_STATE_FILE="./railway-langflow-template.env"
RAILWAY_DEPLOY=true scripts/railway/setup-langflow-split.sh

scripts/railway/create-langflow-template.sh
```

Before publishing the generated template, replace fixed `LANGFLOW_SUPERUSER_PASSWORD` and `LANGFLOW_SECRET_KEY` values in the Railway template editor with template secret variables.
Use `scripts/railway/template-readme.md` as the marketplace README source when publishing.
After that review, publish the draft:

```bash
RAILWAY_TEMPLATE_PUBLISH=true scripts/railway/create-langflow-template.sh
```

When `RAILWAY_TEMPLATE_ID` exists in the state file, the publish command reuses that reviewed draft instead of creating a new one.
