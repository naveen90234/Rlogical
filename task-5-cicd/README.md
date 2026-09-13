# Task 5 — GitHub Actions CI/CD Pipeline

## Application Overview

This is a Node.js Express todo-list application with the following structure:

```
task-5-cicd/
├── src/
│   ├── index.js              # Express app entry point (port 3000)
│   ├── persistence/          # SQLite (default) and Postgres adapters
│   └── routes/               # GET/POST/PUT/DELETE /items handlers
├── spec/                     # Jest test suites
├── Dockerfile                # Multi-stage production image
├── .dockerignore
├── package.json              # node:20, express, sqlite3, pg, jest
└── README.md                 # This file
```

The pipeline workflow lives at:

```
.github/workflows/ci-cd.yml
```

---

## Pipeline Scope — Important

The pipeline is **scoped exclusively to this directory**.  
It triggers **only** when files inside `task-5-cicd/` are changed.  
Changes to `task-1-kubernetes/`, `task-2-nginx/`, `task-3-docker/`, `task-4-backup/`, or `evidence/` will **not** trigger this pipeline.

This is enforced in the workflow via:

```yaml
on:
  push:
    paths:
      - "task-5-cicd/**"
  pull_request:
    paths:
      - "task-5-cicd/**"
```

---

## Pipeline Stages

| # | Stage | Job | Runs On |
|---|---|---|---|
| 1 | App Preparation | `prepare` | All branches |
| 2 | Code Quality (SonarQube) | `code-quality` | All branches |
| 3 | Docker Build | `docker-build` | All branches |
| 4 | Security Scan (Trivy) | `security-scan` | All branches |
| 5 | Push to AWS ECR | `push-to-ecr` | `main` push only |
| 6 | Deploy to EC2 | `deploy` | `main` push only |
| 7 | Health Check | `health-check` | `main` push only |

Stages 5–7 are gated behind:

```yaml
if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

PRs and `develop` branch pushes run only stages 1–4 (build, test, scan) without deploying.

---

## Required GitHub Actions Secrets

Configure all of these under **Settings → Secrets and variables → Actions** in your GitHub repository. Never commit real values.

| Secret | Description | Example |
|---|---|---|
| `AWS_ROLE_ARN` | IAM Role ARN for GitHub OIDC federation | `arn:aws:iam::123456789012:role/github-actions-role` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `ECR_REPOSITORY` | ECR repository name | `nodejs-todo-app` |
| `EC2_HOST` | EC2 public IP or DNS hostname | `54.123.45.67` |
| `EC2_USER` | SSH login username on the EC2 server | `ubuntu` |
| `EC2_SSH_PRIVATE_KEY` | PEM-format private key for SSH | *(full key content)* |
| `SONAR_TOKEN` | SonarQube authentication token | *(generated in SonarQube)* |
| `SONAR_HOST_URL` | SonarQube server URL | `https://sonar.yourcompany.com` |

---

## AWS Authentication — GitHub OIDC (No Long-Lived Keys)

The pipeline uses **GitHub OIDC federation** to assume an IAM Role. No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` are stored anywhere.

### Step 1 — Create the OIDC Identity Provider in AWS IAM

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Or via Console: **IAM → Identity providers → Add provider → OpenID Connect**
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

### Step 2 — Create the IAM Role with Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
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
          "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:*"
        }
      }
    }
  ]
}
```

Replace `<ACCOUNT_ID>`, `<YOUR_GITHUB_ORG>`, and `<YOUR_REPO>` with real values.

### Step 3 — Attach Permissions to the Role

Attach the AWS managed policy:
- `AmazonEC2ContainerRegistryPowerUser` — allows push to ECR

Also attach this inline policy for ECR login from the EC2 server:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    }
  ]
}
```

### Step 4 — Store the Role ARN as a Secret

Set `AWS_ROLE_ARN` = `arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>` in GitHub Secrets.

---

## Docker Workflow (Local)

Use these commands to build and test the image locally before pushing.

```bash
# Build image from inside the task-5-cicd/ directory
cd task-5-cicd

docker build -t nodejs-todo-app:local .

# Run container
docker run -d \
  --name nodejs-todo-app \
  -p 3000:3000 \
  nodejs-todo-app:local

# Verify it is running
docker ps --filter "name=nodejs-todo-app"

# Check logs
docker logs nodejs-todo-app

# Test the app
curl http://localhost:3000/
curl http://localhost:3000/items

# Open a shell inside the container
docker exec -it nodejs-todo-app sh

# Stop and clean up
docker stop nodejs-todo-app
docker rm nodejs-todo-app
docker rmi nodejs-todo-app:local
```

---

## Running Tests Locally

```bash
cd task-5-cicd
npm ci
npm test
```

Jest will run all test files under `spec/`. The app uses SQLite in test mode — no database setup needed.

---

## Triggering the Pipeline

### Trigger CI only (stages 1–4, no deploy)

```bash
git checkout develop
# make a change inside task-5-cicd/
git add task-5-cicd/src/routes/addItem.js
git commit -m "feat: update addItem route"
git push origin develop
# Pipeline runs stages 1-4 only
```

### Trigger full pipeline including deploy (stages 1–7)

```bash
git checkout main
git merge develop
git push origin main
# Pipeline runs all 7 stages
```

### What does NOT trigger the pipeline

```bash
# Changing Kubernetes manifests — pipeline does NOT run
git add task-1-kubernetes/deployment.yaml
git commit -m "chore: update k8s resource limits"
git push origin main
# No pipeline triggered — paths filter excludes this
```

---

## Vulnerability Handling — Trivy (Stage 4)

### Pipeline Behaviour

| Setting | Value | Reason |
|---|---|---|
| `exit-code` | `1` | Pipeline **fails** on HIGH or CRITICAL findings |
| `severity` | `HIGH,CRITICAL` | MEDIUM and below do not block the pipeline |
| `ignore-unfixed` | `true` | CVEs with no available fix are excluded |

### Assumptions

| Area | Assumption |
|---|---|
| Base image | `node:20-alpine` minimises OS-level CVEs. Some unfixed CVEs may exist in the Alpine base — excluded by `ignore-unfixed: true` |
| npm dependencies | Application dependencies are scanned. Developers must keep dependencies up to date via `npm audit` |
| Accepted risk | `ignore-unfixed: true` is set to avoid blocking deployments on CVEs where no upstream fix exists |
| False positives | If a HIGH/CRITICAL CVE is a false positive or accepted risk, add the CVE ID to a `.trivyignore` file in `task-5-cicd/` with a documented justification comment |

### Adding a Vulnerability Exception

Create `task-5-cicd/.trivyignore`:

```
# CVE-YYYY-XXXXX: No fix available in upstream Alpine — tracked in issue #123
CVE-2023-XXXXX
```

### Trivy Scan Results

Results are uploaded as a pipeline artifact named `trivy-scan-results` and retained for 7 days. Download from the GitHub Actions run summary page.

---

## EC2 Server Prerequisites

Before the deploy stage can succeed, the EC2 instance must have:

| Requirement | Details |
|---|---|
| Docker | Installed and running (`sudo systemctl status docker`) |
| AWS CLI v2 | Installed (`aws --version`) |
| IAM Instance Profile | Attached with `ecr:GetAuthorizationToken` and `ecr:BatchGetImage` permissions |
| Security Group | Inbound TCP port `3000` open for the health check |
| SSH access | Public key of `EC2_SSH_PRIVATE_KEY` added to `~/.ssh/authorized_keys` |

### EC2 IAM Instance Profile Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Image Tagging Strategy

| Tag | Format | Purpose |
|---|---|---|
| Versioned | `<short-sha>` (e.g. `a1b2c3d`) | Unique, traceable per-commit identifier |
| `latest` | Always updated on `main` | Convenience tag for pulling most recent build |

The short SHA is generated as `${GITHUB_SHA::7}` and passed between jobs via `outputs`.

---

## Assumptions

1. The application entry point is `src/index.js` and it listens on port `3000`.
2. SQLite is used by default (no external database required for tests or basic runs). Set the `POSTGRES_*` environment variables to switch to Postgres.
3. The `npm test` script runs Jest — all spec files are under `spec/`.
4. SonarQube is either self-hosted or SonarCloud. The `SONAR_HOST_URL` secret handles both.
5. The EC2 deployment target is a single server. For HA deployments replace the SSH step with ECS, EKS, or an Auto Scaling Group rolling update.
6. The application root path `/` returns HTTP 2xx — this is what the health check polls.
