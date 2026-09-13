# DevOps Practical Assessment

A complete submission for the Rlogical DevOps Engineer practical assessment, covering Kubernetes, Nginx, Docker, MySQL backup automation, GitHub Actions CI/CD, and operational troubleshooting.

---

## Repository Structure

```
devops-practical/
├── README.md                          ← This file
├── task-1-kubernetes/
│   ├── deployment.yaml                ← NGINX Kubernetes Deployment (2 replicas, RollingUpdate)
│   └── service.yaml                   ← ClusterIP Service exposing port 80
├── task-2-nginx/
│   └── nginx.conf                     ← Reverse proxy: abc.com → www.abc.com → 127.0.0.1:3000
├── task-3-docker/
│   ├── Dockerfile                     ← Multi-stage Node.js image (node:20-alpine)
│   └── .dockerignore                  ← Excludes node_modules, secrets, build artefacts
├── task-4-backup/
│   ├── backup.sh                      ← MySQL backup → gzip → S3 upload with retention
│   └── retention-approach.md          ← S3 Lifecycle Policy design + IAM policy
├── task-5-cicd/
│   ├── github-actions.yml             ← 7-stage CI/CD pipeline
│   └── README.md                      ← Pipeline secrets, OIDC setup, Trivy assumptions
└── evidence/
    ├── README.md                      ← Testing evidence summary
    ├── troubleshooting-approach.md    ← Task 6: all four troubleshooting scenarios
    └── test-evidence/                 ← Screenshots and command outputs
```

---

## Prerequisites

| Tool | Version | Required For |
|---|---|---|
| `kubectl` | 1.28+ | Task 1 |
| `minikube` or cloud cluster | any | Task 1 live testing |
| `nginx` | 1.24+ | Task 2 |
| `docker` | 24+ | Task 3, Task 5 |
| `node` + `npm` | Node 20 LTS | Task 3 |
| `bash` | 4+ | Task 4 |
| `mysqldump` | 8.0+ | Task 4 |
| `aws` CLI | v2 | Task 4 |
| GitHub Actions | — | Task 5 |
| SonarQube | 9+ or SonarCloud | Task 5 Stage 2 |
| Trivy | latest | Task 5 Stage 4 |

---

## Task 1 — Kubernetes Deployment

### What Was Built
- `deployment.yaml`: Deploys `nginx:latest` with 2 replicas, RollingUpdate strategy (`maxSurge: 1`, `maxUnavailable: 0`), CPU/memory requests and limits, readiness and liveness probes on HTTP `/`.
- `service.yaml`: ClusterIP Service selecting `app: nginx` Pods on port 80.

### Apply the Manifests

```bash
kubectl apply -f task-1-kubernetes/deployment.yaml
kubectl apply -f task-1-kubernetes/service.yaml
```

### Verify

```bash
# Deployment status
kubectl get deployment nginx-deployment

# Pod status (both should show READY 1/1)
kubectl get pods -l app=nginx

# Detailed Pod info (probes, events)
kubectl describe pod -l app=nginx

# Service and endpoints
kubectl get service nginx-service
kubectl get endpoints nginx-service
```

### Confirm Application is Accessible Through the Service

```bash
# Port-forward the Service to localhost for a quick test
kubectl port-forward service/nginx-service 8080:80

# In a separate terminal
curl http://localhost:8080
# Expected: nginx default page HTML (200 OK)
```

### Dry-Run Validation (no cluster needed)

```bash
kubectl apply --dry-run=client -f task-1-kubernetes/deployment.yaml
kubectl apply --dry-run=client -f task-1-kubernetes/service.yaml
```

---

## Task 2 — Nginx Reverse Proxy

### What Was Built
- `nginx.conf` with two server blocks:
  - `abc.com` → HTTP 301 permanent redirect to `http://www.abc.com$request_uri`
  - `www.abc.com` → reverse proxy to `http://127.0.0.1:3000` with standard proxy headers, keep-alive, and buffer tuning

### Validate Configuration Syntax

```bash
# If nginx is installed locally
sudo nginx -t -c /path/to/task-2-nginx/nginx.conf

# Using Docker (no local nginx required)
docker run --rm \
  -v "$(pwd)/task-2-nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:latest nginx -t
```

Expected output:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Deploy to a Server

```bash
sudo cp task-2-nginx/nginx.conf /etc/nginx/sites-available/abc.com
sudo ln -s /etc/nginx/sites-available/abc.com /etc/nginx/sites-enabled/abc.com
sudo nginx -t && sudo systemctl reload nginx
```

### Expected Behaviour

| Request | Behaviour |
|---|---|
| `http://abc.com/` | 301 redirect → `http://www.abc.com/` |
| `http://abc.com/some/path` | 301 redirect → `http://www.abc.com/some/path` |
| `http://www.abc.com/` | Proxied to `http://127.0.0.1:3000/` (200 if app is running) |

### Test with curl

```bash
# Should show: Location: http://www.abc.com/
curl -I http://abc.com

# Should proxy through to the app
curl -v http://www.abc.com
```

### Assumptions
- The backend application is running on `127.0.0.1:3000` on the same server.
- HTTP only (no TLS). In production, add SSL termination with Let's Encrypt or your certificate.
- `abc.com` and `www.abc.com` DNS both point to this server.

---

## Task 3 — Dockerise a Node.js Application

### What Was Built
- `Dockerfile`: Two-stage build — `builder` stage installs all deps and optionally compiles; `production` stage installs only production deps, copies source, runs as a non-root user.
- `.dockerignore`: Excludes `node_modules`, `.env`, `.git`, test files, and editor configs.

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

### Verify Container is Running

```bash
docker ps --filter "name=nodejs-app"
```

### Check Application Logs

```bash
docker logs nodejs-app
docker logs -f nodejs-app   # follow
```

### Access the Running Container

```bash
docker exec -it nodejs-app sh
```

### Test the Application

```bash
curl http://localhost:3000/
```

### Stop, Remove, Clean Up

```bash
# Stop the container
docker stop nodejs-app

# Remove the container
docker rm nodejs-app

# Remove the image
docker rmi nodejs-app:1.0.0
```

### Assumptions
- Entry point is `src/index.js`. If your app uses a different entry point (e.g. `src/server.js` or `dist/index.js`), update the `CMD` in the Dockerfile.
- If the project has a TypeScript or Webpack build step, uncomment `RUN npm run build` in the builder stage and adjust the `COPY` in the production stage to copy from `dist/` instead of `src/`.

---

## Task 4 — MySQL Backup Automation to AWS S3

### What Was Built
- `backup.sh`: Bash script that validates config, checks dependencies, runs `mysqldump | gzip`, uploads to S3, cleans up locally, and enforces 7-day retention.
- `retention-approach.md`: Documents the S3 Lifecycle Policy (primary) and script-based deletion (fallback).

### Required Environment Variables

```bash
export MYSQL_HOST="localhost"          # MySQL server hostname
export MYSQL_PORT="3306"               # MySQL port (default: 3306)
export MYSQL_DATABASE="mydb"           # Database to back up
export MYSQL_USER="backup_user"        # MySQL user
export MYSQL_PASSWORD="<password>"     # MySQL password
export S3_BUCKET="my-backup-bucket"    # S3 bucket name
export AWS_REGION="us-east-1"          # AWS region
export BACKUP_DIR="/tmp/db_backups"    # Local staging dir (default: /tmp/db_backups)
```

Do not hard-code these values. Use a `.env` file (not committed), AWS Secrets Manager, or system environment variables.

### Required Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install -y mysql-client gzip awscli
```

### Required IAM Permissions (EC2 Instance Role)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::my-backup-bucket",
      "arn:aws:s3:::my-backup-bucket/mysql-backups/*"
    ]
  }]
}
```

### Configure and Execute

```bash
# Make executable
chmod +x task-4-backup/backup.sh

# Set environment variables then run
export MYSQL_DATABASE="mydb" MYSQL_USER="backup_user" \
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
# Check S3 for the backup
aws s3 ls s3://my-backup-bucket/mysql-backups/mydb/ --region us-east-1
```

### Verify Backup is Valid

```bash
# Download and inspect
aws s3 cp s3://my-backup-bucket/mysql-backups/mydb/<filename>.sql.gz /tmp/
gunzip -c /tmp/<filename>.sql.gz | head -20
# Should show mysqldump header comments
```

### Failure Handling
- Script uses `set -euo pipefail` — any unhandled error exits immediately with a non-zero code.
- Each critical step (dump, upload) has explicit error checking and logging.
- Partial local files are deleted on failure to avoid stale data.
- Cron exit codes are captured in the log file.

### Retention
S3 Lifecycle Policy (preferred) — see `task-4-backup/retention-approach.md` for the full JSON config and apply command. Script-based deletion is included as a fallback.

---

## Task 5 — GitHub Actions CI/CD Pipeline

### What Was Built
A 7-stage pipeline in `task-5-cicd/github-actions.yml`:

| Stage | Job Name | Trigger |
|---|---|---|
| 1 | App Preparation | All branches |
| 2 | Code Quality (SonarQube) | All branches |
| 3 | Docker Build | All branches |
| 4 | Security Scan (Trivy) | All branches |
| 5 | Push to AWS ECR | `main` push only |
| 6 | Deploy to EC2 | `main` push only |
| 7 | Health Check | `main` push only |

See `task-5-cicd/README.md` for full details on secrets, OIDC setup, EC2 prerequisites, and vulnerability handling.

### Required GitHub Secrets

Configure under **Settings → Secrets and variables → Actions**:

```
AWS_REGION              e.g. us-east-1
AWS_ROLE_ARN            arn:aws:iam::<account>:role/github-actions-role
ECR_REPOSITORY          nodejs-app
EC2_HOST                <EC2 public IP or DNS>
EC2_USER                ubuntu
EC2_SSH_PRIVATE_KEY     <PEM private key content>
SONAR_TOKEN             <SonarQube token>
SONAR_HOST_URL          https://sonar.yourcompany.com
```

### Place the Workflow File

```bash
mkdir -p .github/workflows
cp task-5-cicd/github-actions.yml .github/workflows/ci-cd.yml
```

### Trigger the Pipeline

```bash
git add .github/workflows/ci-cd.yml
git commit -m "ci: add GitHub Actions CI/CD pipeline"
git push origin main
```

Monitor at: `https://github.com/<org>/<repo>/actions`

---

## Task 6 — Troubleshooting

See `evidence/troubleshooting-approach.md` for detailed step-by-step approaches for:

- **Scenario A**: Kubernetes Pod Running but READY 0/1
- **Scenario B**: All Pods running but application not accessible through the Service
- **Scenario C**: Nginx returning 502 Bad Gateway
- **Scenario D**: Ubuntu production server slow, application not responding

---

## Assumptions

1. **Kubernetes**: Target cluster is a standard Kubernetes 1.28+ environment (cloud-managed or self-hosted). The `nginx:latest` image is accessible from the cluster nodes.
2. **Nginx**: Backend application runs on `127.0.0.1:3000` on the same host. HTTP only — TLS termination is out of scope for this task.
3. **Docker**: The Node.js application entry point is `src/index.js`. Build context is the repository root.
4. **Backup**: The EC2 server has an attached IAM Instance Profile. No long-lived AWS credentials are stored on the server.
5. **CI/CD**: SonarQube is self-hosted or SonarCloud. GitHub OIDC federation is used for AWS authentication — no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secrets are used.
6. **Health check**: The deployed application exposes a root path `/` returning HTTP 2xx.
7. **Retention**: S3 Lifecycle Policy is the primary retention mechanism. Script-based fallback is included for environments where lifecycle policies cannot be configured.

---

## Issues Encountered and Resolutions

| Issue | Resolution |
|---|---|
| Multi-stage Docker builds require the `COPY --from` syntax to reference the builder stage | Used `COPY --from=builder /app/src ./src/` in the production stage |
| `mysqldump` password passed via CLI triggers a security warning | Acceptable for a scripted non-interactive context; production alternative is `~/.my.cnf` with restricted permissions |
| Trivy `ignore-unfixed: true` needed to prevent base image CVEs from blocking the pipeline | Documented in `task-5-cicd/README.md` with guidance on when to override |
| GitHub Actions OIDC requires an IAM OIDC provider to be created in the AWS account first | Setup steps documented in `task-5-cicd/README.md` |

---

## AI Usage

### Tool Used
Kiro (AI-powered development environment) was used during this assessment.

### Purpose
- Generating initial boilerplate for Kubernetes manifests, Nginx config, and the GitHub Actions pipeline structure.
- Reviewing the backup script for error handling completeness and bash best practices.
- Cross-referencing documentation for Trivy flags, GitHub OIDC federation setup, and S3 Lifecycle Policy JSON schema.
- Improving consistency and completeness of documentation across README files.

### Manual Review and Modifications
- **Kubernetes**: Resource requests/limits (`cpu: 100m/250m`, `memory: 128Mi/256Mi`) were chosen based on typical nginx resource usage — not generated blindly. Probe `initialDelaySeconds` and `periodSeconds` values were reviewed against nginx startup behaviour.
- **Nginx**: `proxy_buffering` and timeout values were reviewed against official Nginx documentation and adjusted for a typical Node.js application.
- **Dockerfile**: The non-root user creation, `HEALTHCHECK` command, and two-stage structure were reviewed for correctness. The `npm ci --omit=dev` flag was verified as the correct production install command for npm 7+.
- **Backup script**: `set -euo pipefail`, the `validate_config` function, and the S3 retention logic were reviewed line-by-line. The `date -d` vs `date -v` macOS fallback was added manually.
- **CI/CD**: The `concurrency` block, `outputs` passing between jobs, and the health check retry loop were written and verified manually. OIDC trust policy JSON was cross-referenced against the AWS documentation.
- **Troubleshooting**: All commands were verified against knowledge of Linux, Kubernetes, Nginx, and Docker tooling. Decision trees represent genuine diagnostic reasoning, not generated output.

### Validation Approach
- Kubernetes YAML validated with `kubectl apply --dry-run=client`.
- Nginx config validated with `nginx -t` via Docker.
- Bash script reviewed with `shellcheck`.
- GitHub Actions YAML structure verified against the GitHub Actions schema.
- All file paths, flag names, and command syntax cross-checked against official documentation before inclusion.
