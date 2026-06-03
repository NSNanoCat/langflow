# Deploy and Host Langflow Split on Railway

Deploy Langflow as separate frontend, backend, PostgreSQL, and Redis services on Railway.

## About Hosting Langflow Split

This template creates a four-service Langflow deployment:

- `langflow-api`: backend-only Langflow API from `docker/build_and_push_backend.Dockerfile`
- `langflow-web`: nginx-served frontend from `docker/frontend/build_and_push_frontend.Dockerfile`
- `Postgres`: persistent Railway-managed PostgreSQL database
- `Redis`: Railway-managed Redis for Langflow's experimental cache backend

The frontend service proxies `/api` and `/health_check` to `langflow-api` over Railway private networking, so browser traffic stays same-origin while backend-to-backend traffic stays internal.
The web service responds to `/health` locally, and `/health_check` verifies that the web proxy can reach the API and that the API can reach the database.

## Why Deploy Langflow Split on Railway?

Railway gives the deployment a managed database, managed Redis, private service networking, public domains, and GitHub-based redeploys in one project.
Splitting the frontend and backend lets the visual editor and API deploy independently while still keeping the Langflow user experience available from a single public web URL.

This layout is useful when you want to test Langflow production behavior with persistent storage and Redis caching without maintaining custom infrastructure.

## Common Use Cases

- Run a persistent Langflow visual builder with PostgreSQL-backed flow storage.
- Keep the frontend and API as separate Railway services for independent deploys.
- Validate Langflow's Redis cache backend in a managed environment.
- Clone or reset a complete Langflow stack for repeated test deployments.

## Dependencies for Langflow Split

The template depends on:

- A GitHub source connection for `NSNanoCat/langflow`
- Railway-managed PostgreSQL
- Railway-managed Redis
- Railway private networking between `langflow-web`, `langflow-api`, `Postgres`, and `Redis`

### Deployment Dependencies

The API service expects these variables:

```text
LANGFLOW_BACKEND_ONLY=True
LANGFLOW_HOST=0.0.0.0
PORT=7860
LANGFLOW_PORT=7860
LANGFLOW_DATABASE_URL=${{Postgres.DATABASE_URL}}
LANGFLOW_ALEMBIC_LOG_TO_STDOUT=True
LANGFLOW_AUTO_LOGIN=False
LANGFLOW_SUPERUSER=admin
LANGFLOW_SUPERUSER_PASSWORD=<template-secret>
LANGFLOW_SECRET_KEY=<template-secret>
LANGFLOW_CACHE_TYPE=redis
LANGFLOW_REDIS_URL=${{Redis.REDIS_URL}}
```

The web service expects:

```text
BACKEND_URL=http://${{langflow-api.RAILWAY_PRIVATE_DOMAIN}}:7860
```

Use a Fernet-compatible value for `LANGFLOW_SECRET_KEY`.
For reusable publishing, configure `LANGFLOW_SUPERUSER_PASSWORD` and `LANGFLOW_SECRET_KEY` as secret template variables instead of fixed project values.

## Validation

After deployment, open:

- `/` on the `langflow-web` public domain
- `/health` on the `langflow-web` public domain
- `/health_check` on the `langflow-web` public domain

The `/health_check` response should include `db` and `chat` status values from the backend.
