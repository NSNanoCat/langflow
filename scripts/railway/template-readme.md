# Langflow split Railway deployment

Deploy Langflow as four Railway services:

- `langflow-api`: backend-only Langflow API
- `langflow-web`: nginx-served frontend with same-origin API proxying
- `Postgres`: persistent database
- `Redis`: Langflow experimental cache backend

## Services

The API service runs from `docker/build_and_push_backend.Dockerfile` with `LANGFLOW_BACKEND_ONLY=True`.
The web service runs from `docker/frontend/build_and_push_frontend.Dockerfile` and proxies `/api` and `/health_check` to `langflow-api` over Railway private networking.
The web service responds to `/health` locally so frontend health checks do not depend on backend startup timing.

## Required variables

The template must set these on `langflow-api`:

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

The template must set this on `langflow-web`:

```text
BACKEND_URL=http://${{langflow-api.RAILWAY_PRIVATE_DOMAIN}}:7860
```

Use a Fernet-compatible value for `LANGFLOW_SECRET_KEY`.
For template publishing, configure both `LANGFLOW_SUPERUSER_PASSWORD` and `LANGFLOW_SECRET_KEY` as secret template variables instead of fixed project values.

## Validation

After deployment, open:

- `/` on the `langflow-web` public domain
- `/health` on the `langflow-web` public domain
- `/health_check` on the `langflow-web` public domain

The `/health_check` response should include `db` and `chat` status values from the backend.
