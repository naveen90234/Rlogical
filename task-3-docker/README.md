# Task 3 — Dockerise a Node.js Application

## Overview

Dockerfile and `.dockerignore` to containerise a Node.js application. The image uses `node:20-alpine` as the base for a minimal footprint.

## Files

| File | Description |
|---|---|
| `Dockerfile` | Single-stage Node.js image based on `node:20-alpine` |
| `.dockerignore` | Excludes `node_modules`, secrets, build artefacts, tests, and editor files |

## Dockerfile Details

| Setting | Value |
|---|---|
| Base image | `node:20-alpine` |
| Working directory | `/app` |
| Exposed port | `3000` |
| Entry point | `npm start` |
| Dependency install | `npm ci` (clean install from lock file) |

## Prerequisites

- Docker 24+
- Node.js application with `package.json`, `package-lock.json`, and `src/` directory

## Build the Image

```bash
docker build -t nodejs-app:1.0.0 .
```

## Run the Container

```bash
docker run -d \
  --name nodejs-app \
  -p 3000:3000 \
  nodejs-app:1.0.0
```

## Verify Container is Running

```bash
docker ps --filter "name=nodejs-app"
```

## Check Application Logs

```bash
docker logs nodejs-app
docker logs -f nodejs-app
```

## Access the Running Container

```bash
docker exec -it nodejs-app sh
```

## Test the Application

```bash
curl http://localhost:3000/
```

## Stop the Container

```bash
docker stop nodejs-app
```

## Remove the Container

```bash
docker rm nodejs-app
```

## Remove the Image

```bash
docker rmi nodejs-app:1.0.0
```

## Full Workflow Example

```bash
# Build
docker build -t nodejs-app:1.0.0 .

# Run
docker run -d --name nodejs-app -p 3000:3000 nodejs-app:1.0.0

# Verify
docker ps --filter "name=nodejs-app"

# Logs
docker logs nodejs-app

# Test
curl http://localhost:3000/

# Shell access
docker exec -it nodejs-app sh

# Stop and clean up
docker stop nodejs-app
docker rm nodejs-app
docker rmi nodejs-app:1.0.0
```

## Assumptions

- Application entry point is `npm start` defined in `package.json`.
- Application listens on port `3000`.
- `src/` directory contains the application source code.
