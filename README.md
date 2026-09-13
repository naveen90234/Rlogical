# DevOps Practical Assessment

Submission for the Rlogical DevOps Engineer practical assessment.

---

## Repository Structure

```
devops-practical/
├── README.md                            ← This file
├── .github/
│   └── workflows/
│       └── ci-cd.yml                    ← GitHub Actions pipeline (Task 5 only)
│
├── task-1-kubernetes/
│   ├── deployment.yaml                  ← NGINX Deployment: 2 replicas, RollingUpdate, probes
│   └── service.yaml                     ← ClusterIP Service on port 80
│
├── task-2-nginx/
│   └── nginx.conf                       ← 301 redirect abc.com→www.abc.com, reverse proxy to :3000
│
├── task-3-docker/
│   ├── Dockerfile                       ← Multi-stage Node.js image (node:20-alpine)
│   └── .dockerignore
│
├── task-4-backup/
│   ├── backup.sh                        ← MySQL → gzip → S3 with retention
│   └── retention-approach.md           ← S3 Lifecycle Policy design + IAM policy
│
├── task-5-cicd/                         ← Node.js todo app + its own Dockerfile
│   ├── src/                             ← Express app (index.js, routes/, persistence/)
│   ├── spec/                            ← Jest tests
│   ├── Dockerfile                       ← Production image for this app
│   ├── .dockerignore
│   ├── package.json
│   └── README.md                        ← Pipeline docs, secrets, OIDC setup
│
└── evidence/
    ├── README.md                        ← Testing evidence summary
    ├── troubleshooting-approach.md      ← Task 6: all four scenarios
    └── test-evidence/                   ← Screenshots and command outputs
```

---

## Prerequisites

| Tool | Version | Required For |
|---|---|---|
| `kubectl` | 1.28+ | Task 1 |
| Kubernetes cluster (minikube / cloud) | any | Task 1 live testing |
| `nginx` | 1.24+ | Task 2 |
| `docker` | 24+ | Task 3, Task 5 |
| `node` + `npm` | 20 LTS | Task 3, Task 5 |
| `bash` | 4+ | Task 4 |
| `mysqldump` (mysql-client) | 8.0+ | Task 4 |
| `aws` CLI | v2 | Task 4 |
| GitHub repository | — | Task 5 |
| SonarQube (self-hosted or SonarCloud) | 9+ | Task 5 Stage 2 |
| AWS ECR repository | — | Task 5 Stage 5 |
| Ubuntu EC2 instance with Docker | — | Task 5 Stage 6 |

---

## Task 1 — Kubernetes Deployment

### What Was Built

| File | Description |
|---|---|
| `deployment.yaml` | Deploys `nginx:latest`, 2 replicas, RollingUpdate (`maxSurge: 1`, `maxUnavailable: 0`), readiness + liveness probes on HTTP `/`, CPU and memory requests/limits |
| `service.yaml` | ClusterIP Service, selector `app: nginx`, port 80 |

### Apply the Manifests

```bash
kubectl apply -f task-1-kubernetes/deployment.yaml
kubectl apply -f task-1-kubernetes/service.yaml
```

### Verify the Deployment

```bash
# Deployment rollout status
kubectl rollout status deployment/nginx-deployment

# Deployment summary
kubectl get deployment nginx-deployment

# Pod status — both pods should show READY 1/1
kubectl get pods -l app=nginx

# Full pod details including probe status and events
kubectl describe pod -l app=nginx
```

### Verify the Service

```bash
kubectl get service nginx-service
kubectl get endpoints nginx-service
# Endpoints should show two Pod IPs on port 80
```

### Confirm Application is Accessible Through the Service

```bash
# Port-forward to test locally
kubectl port-forward service/nginx-service 8080:80

# In a separate terminal
curl http://localhost:8080
# Expected: nginx default page (HTTP 200)
```

### Dry-Run Validation (no cluster needed)

```bash
kubectl apply --dry-run=client -f task-1-kubernetes/deployment.yaml
kubectl apply --dry-run=client -f task-1-kubernetes/service.yaml
```

### Assumptions

- Target is a standard Kubernetes 1.28+ cluster (minikube, EKS, GKE, AKS, or kubeadm).
- `nginx:latest` is reachable from the cluster nodes (internet access or private registry mirror).
- Resource values (`cpu: 100m/250m`, `memory: 128Mi/256Mi`) are appropriate for a basic nginx workload and may need tuning in production.

---

## Task 2 — Nginx Reverse Proxy

### What Was Built

`nginx.conf` contains two server blocks:

| Server Block | Behaviour |
|---|---|
| `abc.com` | HTTP 301 permanent redirect to `http://www.abc.com$request_uri` |
| `www.abc.com` | Reverse proxy to upstream `http://127.0.0.1:3000` |

Includes: proxy headers (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`), keep-alive, connect/send/read timeouts, proxy buffering.

### Validate Configuration Syntax

```bash
# If nginx is installed locally
sudo nginx -t -c $(pwd)/task-2-nginx/nginx.conf

# Using Docker — no local nginx installation needed
docker run --rm \
  -v "$(pwd)/task-2-nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:latest nginx -t
```

Expected output:
```
nginx: the configuration file ... syntax is ok
nginx: configuration file ... test is successful
```

### Deploy to a Server

```bash
sudo cp task-2-nginx/nginx.conf /etc/nginx/sites-available/abc.com
sudo ln -sf /etc/nginx/sites-available/abc.com /etc/nginx/sites-enabled/abc.com
sudo nginx -t && sudo systemctl reload nginx
```

### Expected Behaviour

| Request | Response |
|---|---|
| `http://abc.com/` | `301 Moved Permanently` → `http://www.abc.com/` |
| `http://abc.com/some/path` | `301` → `http://www.abc.com/some/path` |
| `http://www.abc.com/` | Proxied to `http://127.0.0.1:3000/` — response from the backend app |

### Test with curl

```bash
# Should return: Location: http://www.abc.com/
curl -I http://abc.com

# Should proxy to the backend app
curl -v http://www.abc.com
```

### Assumptions

- Backend application runs on `127.0.0.1:3000` on the same host as nginx.
- HTTP only — TLS/SSL termination is out of scope. In production add Let's Encrypt or your certificate provider.
- DNS for both `abc.com` and `www.abc.com` points to this server.

---

## Task 3 — Dockerise a Node.js Application

### What Was Built

| File | Description |
|---|---|
| `Dockerfile` | Two-stage build: `builder` installs all deps; `production` stage installs only production deps, runs as non-root user `appuser` |
| `.dockerignore` | Excludes `node_modules`, `.env`, `.git`, tests, editor configs, OS artefacts |

### Build the Image

```bash
cd task-3-docker
docker build -t nodejs-app:1.0.0 .
```

### Run the Container

```bash
docker run -d \
  --name nodejs-app \
  -p 3000:3000 \
  --restart unless-stopped \
  nodejs-app:1.0.0
```

### Verify the Container is Running

```bash
docker ps --filter "name=nodejs-app"
```

### Check Application Logs

```bash
docker logs nodejs-app
docker logs -f nodejs-app    # follow live
```

### Access the Running Container

```bash
docker exec -it nodejs-app sh
```

### Test the Application

```bash
curl http://localhost:3000/
```

### Stop, Remove, and Clean Up

```bash
docker stop nodejs-app
docker rm nodejs-app
docker rmi nodejs-app:1.0.0
```

### Assumptions

- Entry point is `src/index.js`. Update `CMD` in the Dockerfile if your project uses a different entry (e.g. `dist/index.js`).
- If the project has a TypeScript or Webpack build step, uncomment `RUN npm run build` in the builder stage and adjust the `COPY` in the production stage accordingly.

---

## Task 4 — MySQL Backup Automation to AWS S3

### What Was Built

| File | Description |
|---|---|
| `backup.sh` | Validates config, checks dependencies, `mysqldump \| gzip`, uploads to S3, cleans up local file, enforces 7-day retention |
| `retention-approach.md` | S3 Lifecycle Policy (preferred), script-based deletion (fallback), IAM policy |

### Required Environment Variables

Set these in your environment or a secrets manager — never hard-code them in the script.

```bash
export MYSQL_HOST="localhost"          # Default: localhost
export MYSQL_PORT="3306"               # Default: 3306
export MYSQL_DATABASE="myappdb"        # REQUIRED
export MYSQL_USER="backup_user"        # REQUIRED
export MYSQL_PASSWORD="<password>"     # REQUIRED
export S3_BUCKET="my-backup-bucket"   # REQUIRED
export AWS_REGION="us-east-1"         # Default: us-east-1
export BACKUP_DIR="/tmp/db_backups"   # Default: /tmp/db_backups
```

### Required Dependencies (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y mysql-client gzip
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
```

### Required IAM Permissions (EC2 Instance Role — no long-lived keys)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::my-backup-bucket",
      "arn:aws:s3:::my-backup-bucket/mysql-backups/*"
    ]
  }]
}
```

### Execute the Script

```bash
chmod +x task-4-backup/backup.sh

# Set env vars then run
export MYSQL_DATABASE="myappdb" MYSQL_USER="backup_user" \
       MYSQL_PASSWORD="secret" S3_BUCKET="my-backup-bucket" \
       AWS_REGION="us-east-1"

./task-4-backup/backup.sh
```

### Automate with Cron (Daily at 2 AM)

```bash
crontab -e
# Add:
0 2 * * * /opt/scripts/backup.sh >> /var/log/mysql-backup.log 2>&1
```

### Verify Backup Was Created

```bash
# List backups in S3
aws s3 ls s3://my-backup-bucket/mysql-backups/myappdb/ --region us-east-1

# Download and verify the backup is a valid SQL dump
aws s3 cp s3://my-backup-bucket/mysql-backups/myappdb/<filename>.sql.gz /tmp/
gunzip -c /tmp/<filename>.sql.gz | head -20
# Should show: -- MySQL dump 10.x ...
```

### Verify Upload to S3

```bash
aws s3api head-object \
  --bucket my-backup-bucket \
  --key "mysql-backups/myappdb/<filename>.sql.gz" \
  --region us-east-1
```

### Failure Handling

- `set -euo pipefail` — any unhandled error exits immediately with a non-zero code.
- Each critical operation (dump, upload) has explicit error checking and removes partial files on failure.
- Cron exit codes are written to the log file for auditing.
- Non-zero exit code is returned on any critical failure.

### Backup Retention

S3 Lifecycle Policy (7-day expiry on `mysql-backups/` prefix) is the primary approach. See `task-4-backup/retention-approach.md` for the full JSON config and the `aws s3api put-bucket-lifecycle-configuration` command to apply it. Script-based deletion is included in `backup.sh` as a fallback.

---

## Task 5 — GitHub Actions CI/CD Pipeline

### Pipeline Scope

**The pipeline only triggers when files inside `task-5-cicd/` are modified.**  
No other task folder will ever trigger this pipeline.

```
.github/workflows/ci-cd.yml   ← workflow definition
task-5-cicd/                  ← the only directory that triggers the pipeline
```

### Application

A Node.js Express todo-list app:
- Entry point: `task-5-cicd/src/index.js`
- Port: `3000`
- Database: SQLite (default) or Postgres
- Tests: Jest, under `task-5-cicd/spec/`

### Pipeline Stages

| Stage | What It Does |
|---|---|
| 1 — App Preparation | Checkout, `node:20` setup, `npm ci`, `npm test` |
| 2 — Code Quality | SonarQube scan + Quality Gate |
| 3 — Docker Build | Build image tagged `<short-sha>`, cache via GitHub Actions cache |
| 4 — Security Scan | Trivy — fails on `HIGH` or `CRITICAL` vulnerabilities |
| 5 — Push to ECR | OIDC auth, tag + push versioned and `latest` to AWS ECR |
| 6 — Deploy to EC2 | SSH, `docker pull`, stop old container, start new container |
| 7 — Health Check | `curl` with retries against `http://<EC2_HOST>:3000` |

### Required Secrets

See `task-5-cicd/README.md` for the full secrets table, OIDC setup steps, EC2 prerequisites, and Trivy vulnerability handling assumptions.

### Trigger the Pipeline

```bash
# Trigger CI only (stages 1–4)
git checkout develop
echo "# change" >> task-5-cicd/src/index.js
git add task-5-cicd/src/index.js
git commit -m "ci: test pipeline trigger"
git push origin develop

# Trigger full deploy (stages 1–7)
git checkout main
git merge develop
git push origin main
```

### Place the Workflow

The workflow file is already at `.github/workflows/ci-cd.yml`. No manual copying needed — GitHub Actions picks it up automatically once the repository is pushed to GitHub.

---

## Task 6 — Troubleshooting

See `evidence/troubleshooting-approach.md` for detailed step-by-step approaches for all four scenarios:

| Scenario | Topic |
|---|---|
| A | Kubernetes Pod STATUS Running, READY 0/1 |
| B | All Pods running but application not accessible through the Service |
| C | Nginx returning 502 Bad Gateway |
| D | Ubuntu production server slow, application not responding |

Each scenario includes: what to check first and why, exact commands, what to look for in each output, and a resolution decision tree.

---

## Assumptions

1. **Kubernetes**: Standard Kubernetes 1.28+ cluster. `nginx:latest` is reachable from nodes.
2. **Nginx**: Backend runs on `127.0.0.1:3000` on the same host. HTTP only — TLS is out of scope.
3. **Docker (Task 3)**: Entry point is `src/index.js`. The generic Dockerfile in `task-3-docker/` is separate from the app-specific one in `task-5-cicd/`.
4. **Backup**: EC2 server uses an IAM Instance Profile. No AWS Access Key or Secret Key is stored on the server.
5. **CI/CD**: GitHub OIDC federation is used — no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secrets. The pipeline only triggers on `task-5-cicd/**` path changes.
6. **Health check**: The deployed app's root path `/` returns HTTP 2xx.
7. **Retention**: S3 Lifecycle Policy is the primary retention mechanism; script-based deletion in `backup.sh` is the fallback.

---

## Issues Encountered and Resolutions

| Issue | Resolution |
|---|---|
| CI/CD pipeline was initially written without path scoping — would trigger on any file change | Added `paths: ["task-5-cicd/**"]` to both `push` and `pull_request` triggers |
| The generic Dockerfile in `task-3-docker/` does not match the real app structure in `task-5-cicd/` | Created a separate `task-5-cicd/Dockerfile` using the actual `src/index.js` entry point |
| `mysqldump --password` on CLI triggers a security warning in MySQL 8.0+ | Acceptable for a scripted non-interactive context; production alternative is a `~/.my.cnf` file with `chmod 600` |
| Trivy blocks on base image CVEs with no upstream fix | Set `ignore-unfixed: true` to skip unfixable CVEs; documented in `task-5-cicd/README.md` |
| GitHub Actions OIDC requires an IAM OIDC provider created in the AWS account before it works | Full setup steps documented in `task-5-cicd/README.md` |

---

## AI Usage

### Tool Used

Kiro (AI-powered development environment built on VS Code) was used throughout this assessment.

### Purpose

- Generating initial boilerplate for Kubernetes manifests, Nginx config, and the GitHub Actions pipeline structure.
- Reviewing the backup script for `bash` best practices and error handling completeness.
- Cross-referencing documentation for Trivy CLI flags, GitHub OIDC federation setup, and S3 Lifecycle Policy JSON schema.
- Structuring and improving consistency of documentation across all README files.

### What Was Manually Reviewed and Modified

- **Kubernetes**: Resource requests/limits chosen based on nginx workload characteristics. Probe `initialDelaySeconds` and `timeoutSeconds` reviewed against actual nginx startup behaviour.
- **Nginx**: Timeout values and `proxy_buffering` settings reviewed against official Nginx documentation and adjusted for Node.js upstream behaviour.
- **Dockerfile (task-5-cicd)**: After reading the actual app code (`src/index.js`, `package.json`), the Dockerfile was written to match — `node src/index.js` entry point, `sqlite3` native dep compatibility on Alpine confirmed, non-root user pattern verified.
- **Backup script**: `set -euo pipefail`, `validate_config()`, and the S3 retention logic reviewed line by line. The `date -d` vs `date -v` macOS fallback was added manually after checking GNU/BSD date incompatibility.
- **CI/CD**: The `paths` trigger filter, `defaults.run.working-directory`, `outputs` passing between jobs, and the health check retry loop were written and verified manually. OIDC trust policy JSON cross-referenced against AWS documentation.
- **Troubleshooting**: All commands verified against direct knowledge of Linux, Kubernetes, Nginx, and Docker tooling. Decision trees represent genuine diagnostic reasoning.

### How AI-Generated Output Was Validated

- Kubernetes YAML validated with `kubectl apply --dry-run=client`.
- Nginx config validated with `nginx -t` via Docker.
- Bash script reviewed with `shellcheck`.
- GitHub Actions YAML structure cross-checked against the GitHub Actions schema documentation.
- All CLI flag names, YAML keys, and command syntax verified against official documentation before inclusion.
