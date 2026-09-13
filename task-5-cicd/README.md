# Task 5 — GitHub Actions CI/CD Pipeline

## Overview

GitHub Actions CI/CD pipeline for a Node.js Express todo-list application. The pipeline is **scoped exclusively to the `task-5-cicd/` directory** — changes to any other task folder will not trigger it.

## Application

| Property | Value |
|---|---|
| Framework | Express.js |
| Entry point | `src/index.js` |
| Port | `3000` |
| Database | SQLite (default) / PostgreSQL |
| Tests | Jest (under `spec/`) |

## Files

| File | Description |
|---|---|
| `src/` | Express application source code |
| `spec/` | Jest test suites |
| `Dockerfile` | Production Docker image (`node:20-alpine`) |
| `.dockerignore` | Excludes `node_modules`, `spec/`, `.env`, `.git` |
| `package.json` | Node.js dependencies and scripts |
| `sonar-project.properties` | SonarQube configuration (`projectKey=Rlogical`) |

## Pipeline Location

```
.github/workflows/ci-cd.yml
```

## Pipeline Trigger

Only fires when files inside `task-5-cicd/` are changed:

```yaml
on:
  push:
    branches: [dev]
    paths: ["task-5-cicd/**"]
  pull_request:
    branches: [dev]
    paths: ["task-5-cicd/**"]
```

## Runner

| Property | Value |
|---|---|
| Runner name | `rlogical-ec2-runner` |
| Labels | `[ubuntu, ec2, rlogical]` |
| Type | Self-hosted on EC2 |

## Pipeline Stages

| Stage | Job | Runs On | Description |
|---|---|---|---|
| 1 | `prepare` | All events | Checkout, Node.js 20 setup, `npm ci`, `npm test` |
| 2 | `code-quality` | All events | SonarQube scan + Quality Gate (`projectKey=Rlogical`) |
| 3 | `docker-build` | All events | Build image tagged with short Git SHA |
| 4 | `security-scan` | All events | Trivy scan — report only, does not block pipeline |
| 5 | `push-to-ecr` | `dev` push only | OIDC auth, push versioned + `latest` tags to ECR |
| 6 | `deploy` | `dev` push only | SSH to EC2, pull image, restart container |
| 7 | `health-check` | `dev` push only | HTTP poll with retries against deployed app |

## Environment

All jobs run in the `dev` GitHub Actions environment. Stages 5–7 only run on direct pushes to `dev`, not on pull requests.

## Required GitHub Actions Secrets

| Secret | Description |
|---|---|
| `SONAR_TOKEN` | SonarQube authentication token |
| `SONAR_HOST_URL` | SonarQube server URL (e.g. `http://3.106.56.33:9000`) |
| `AWS_ROLE_ARN` | IAM Role ARN for GitHub OIDC federation |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `ECR_REPOSITORY` | ECR repository name |
| `EC2_HOST` | EC2 public IP or DNS |
| `EC2_USER` | SSH username (e.g. `ubuntu`) |
| `EC2_SSH_PRIVATE_KEY` | PEM private key for SSH access |

## AWS Authentication — GitHub OIDC (No Long-Lived Keys)

No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` are stored. The pipeline uses GitHub OIDC federation to assume an IAM Role.

### Setup

1. Create OIDC provider in IAM:
   - URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. Create IAM Role with trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:naveen90234/Rlogical:*"
      }
    }
  }]
}
```

3. Attach `AmazonEC2ContainerRegistryPowerUser` policy to the role.
4. Store the Role ARN as `AWS_ROLE_ARN` secret.

## SonarQube Configuration

SonarQube is self-hosted on the EC2 server at `http://3.106.56.33:9000`.

The project key and server URL are set in `sonar-project.properties`:

```properties
sonar.projectKey=Rlogical
sonar.projectName=Rlogical
sonar.host.url=http://3.106.56.33:9000
sonar.sources=src
sonar.tests=spec
sonar.exclusions=node_modules/**,src/static/**
```

## Trivy Security Scan

| Setting | Value |
|---|---|
| Severity | `HIGH, CRITICAL` |
| Exit code | `0` (report only, never blocks pipeline) |
| Ignore unfixed | `true` |
| Results | Uploaded as `trivy-scan-results` artifact, retained 7 days |

## Docker Workflow (Local)

```bash
cd task-5-cicd

# Build
docker build -t nodejs-todo-app:local .

# Run
docker run -d --name nodejs-todo-app -p 3000:3000 nodejs-todo-app:local

# Verify
docker ps --filter "name=nodejs-todo-app"

# Logs
docker logs nodejs-todo-app

# Test
curl http://localhost:3000/
curl http://localhost:3000/items

# Shell
docker exec -it nodejs-todo-app sh

# Clean up
docker stop nodejs-todo-app && docker rm nodejs-todo-app
docker rmi nodejs-todo-app:local
```

## Run Tests Locally

```bash
cd task-5-cicd
npm ci
npm test
```

## Trigger the Pipeline

```bash
# Make a change inside task-5-cicd/
echo "# trigger" >> task-5-cicd/src/index.js
git add task-5-cicd/src/index.js
git commit -m "feat: update app"
git push origin dev
# Pipeline triggers on dev branch for task-5-cicd/** changes only
```

## EC2 Server Prerequisites

| Requirement | Details |
|---|---|
| Docker | Installed and running |
| AWS CLI v2 | Installed |
| IAM Instance Profile | `ecr:GetAuthorizationToken`, `ecr:BatchGetImage` |
| Security Group | Inbound TCP port `3000` open |
| SSH | Public key of `EC2_SSH_PRIVATE_KEY` in `~/.ssh/authorized_keys` |
