# DevOps Practical Assessment

Submission for the Rlogical DevOps Engineer practical assessment covering Kubernetes, Nginx, Docker, MySQL backup automation, GitHub Actions CI/CD, and operational troubleshooting.

---

## Repository Structure

```
devops-practical/
├── README.md                            ← This file
│
├── .github/
│   └── workflows/
│       └── ci-cd.yml                    ← CI/CD pipeline (task-5-cicd/** trigger only)
│
├── task-1-kubernetes/
│   ├── README.md                        ← Setup and validation commands
│   ├── deployment.yaml                  ← NGINX Deployment: 2 replicas, RollingUpdate, probes
│   └── service.yaml                     ← ClusterIP Service on port 80
│
├── task-2-nginx/
│   ├── README.md                        ← Configuration details and test commands
│   └── nginx.conf                       ← 301 redirect + reverse proxy to :3000
│
├── task-3-docker/
│   ├── README.md                        ← Build, run, and cleanup commands
│   ├── Dockerfile                       ← Node.js image (node:20-alpine)
│   └── .dockerignore                    ← Excludes node_modules, secrets, artefacts
│
├── task-4-backup/
│   ├── README.md                        ← Configuration, execution, and validation
│   ├── backup.sh                        ← MySQL → gzip → S3 with retention
│   ├── lifecycle.json                   ← S3 Lifecycle Policy (7-day retention)
│   └── retention-approach.md           ← Decision: S3 Lifecycle Policy vs script
│
├── task-5-cicd/
│   ├── README.md                        ← Pipeline docs, secrets, OIDC setup
│   ├── src/                             ← Express todo-list application
│   ├── spec/                            ← Jest tests
│   ├── Dockerfile                       ← Production image for this application
│   ├── .dockerignore
│   ├── package.json
│   └── sonar-project.properties        ← SonarQube config (projectKey=Rlogical)
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
| Kubernetes cluster | any | Task 1 live testing |
| `nginx` | 1.24+ | Task 2 |
| `docker` | 24+ | Task 3, Task 5 |
| `node` + `npm` | 20 LTS | Task 3, Task 5 |
| `bash` | 4+ | Task 4 |
| `mysql-client` | 8.0+ | Task 4 |
| `aws` CLI | v2 | Task 4 |
| GitHub repository | — | Task 5 |
| SonarQube | 9+ | Task 5 Stage 2 |
| AWS ECR | — | Task 5 Stage 5 |
| Ubuntu EC2 with Docker | — | Task 5 Stage 6 |

---

## Task 1 — Kubernetes Deployment

Deploys `nginx:latest` with 2 replicas, RollingUpdate strategy, readiness and liveness probes, and a ClusterIP Service.

```bash
kubectl apply -f task-1-kubernetes/deployment.yaml
kubectl apply -f task-1-kubernetes/service.yaml

kubectl get deployment nginx-deployment
kubectl get pods -l app=nginx
kubectl get service nginx-service

# Test access through the service
kubectl port-forward service/nginx-service 8080:80
curl http://localhost:8080
```

See `task-1-kubernetes/README.md` for full details.

---

## Task 2 — Nginx Reverse Proxy

Nginx configuration with two server blocks:
- `abc.com` → HTTP 301 permanent redirect to `http://www.abc.com$request_uri`
- `www.abc.com` → Reverse proxy to `http://127.0.0.1:3000`

```bash
# Validate syntax using Docker
docker run --rm \
  -v "$(pwd)/task-2-nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:latest nginx -t

# Deploy
sudo cp task-2-nginx/nginx.conf /etc/nginx/sites-available/abc.com
sudo ln -sf /etc/nginx/sites-available/abc.com /etc/nginx/sites-enabled/abc.com
sudo nginx -t && sudo systemctl reload nginx

# Test
curl -I http://abc.com        # Expected: 301 -> http://www.abc.com/
curl -v http://www.abc.com    # Expected: proxied response from :3000
```

See `task-2-nginx/README.md` for full details.

---

## Task 3 — Dockerise a Node.js Application

Dockerfile using `node:20-alpine` base image. Dependencies installed before source copy for Docker layer caching.

```bash
docker build -t nodejs-app:1.0.0 .
docker run -d --name nodejs-app -p 3000:3000 nodejs-app:1.0.0
docker ps --filter "name=nodejs-app"
curl http://localhost:3000/
docker stop nodejs-app && docker rm nodejs-app
docker rmi nodejs-app:1.0.0
```

See `task-3-docker/README.md` for full workflow.

---

## Task 4 — MySQL Backup Automation to AWS S3

Bash script: `mysqldump` → `gzip` → S3 upload → 7-day retention via S3 Lifecycle Policy.

```bash
# Set environment variables
export MYSQL_DATABASE="myappdb"
export MYSQL_USER="backup_user"
export MYSQL_PASSWORD="your_password"
export S3_BUCKET="your-backup-bucket"
export AWS_REGION="us-east-1"

# Run backup
chmod +x task-4-backup/backup.sh
./task-4-backup/backup.sh

# Apply S3 Lifecycle Policy (7-day retention)
aws s3api put-bucket-lifecycle-configuration \
  --bucket your-backup-bucket \
  --lifecycle-configuration file://task-4-backup/lifecycle.json

# Verify backup in S3
aws s3 ls s3://your-backup-bucket/mysql-backups/myappdb/
```

See `task-4-backup/README.md` for full details.

---

## Task 5 — GitHub Actions CI/CD Pipeline

7-stage pipeline for the Node.js todo-list application. **Triggers only on changes inside `task-5-cicd/`.**

| Stage | Description |
|---|---|
| 1 — Prepare | Checkout, Node.js 20, `npm ci`, `npm test` |
| 2 — Code Quality | SonarQube analysis (`projectKey=Rlogical`) |
| 3 — Docker Build | Image tagged with short Git SHA |
| 4 — Security Scan | Trivy — report only, never blocks |
| 5 — Push to ECR | GitHub OIDC auth, push to AWS ECR |
| 6 — Deploy to EC2 | SSH, pull image, restart container |
| 7 — Health Check | HTTP poll with retries |

Runner: `rlogical-ec2-runner` with labels `[ubuntu, ec2, rlogical]`  
Branch: `dev` | Environment: `dev`

```bash
# Trigger pipeline
git checkout dev
# make a change inside task-5-cicd/
git add task-5-cicd/
git commit -m "feat: update app"
git push origin dev
```

See `task-5-cicd/README.md` for secrets setup, OIDC configuration, and Docker workflow.

---

## Task 6 — Troubleshooting

See `evidence/troubleshooting-approach.md` for step-by-step investigation approaches for all four scenarios:

| Scenario | Topic |
|---|---|
| A | Kubernetes Pod `STATUS: Running`, `READY: 0/1` |
| B | All Pods running but application not accessible through Service |
| C | Nginx returning `502 Bad Gateway` |
| D | Ubuntu production server slow, application not responding |

---

## Assumptions

1. **Kubernetes**: Standard 1.28+ cluster. `nginx:latest` accessible from nodes.
2. **Nginx**: Backend on `127.0.0.1:3000` same host. HTTP only — TLS out of scope.
3. **Docker**: App entry point is `npm start`. Port `3000`.
4. **Backup**: EC2 uses IAM Instance Profile. No AWS keys stored on server.
5. **CI/CD**: GitHub OIDC used — no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. Pipeline scoped to `task-5-cicd/**` only.
6. **Health check**: App root path `/` returns HTTP 2xx.
7. **Retention**: S3 Lifecycle Policy is primary; script-based deletion in `backup.sh` is fallback.

---

## Issues Encountered and Resolutions

| Issue | Resolution |
|---|---|
| `SONAR_HOST_URL` secret had trailing newline — caused `invalid header value` error | Hardcoded URL in workflow env and `sonar-project.properties`. SonarQube steps commented pending secret cleanup |
| Trivy exited with code 1 blocking the pipeline | Set `exit-code: "0"` — scan generates report as artifact without blocking |
| Remote CI/CD diverged from local due to concurrent edits on GitHub | Used `git pull --no-rebase` + conflict resolution to sync |
| Pipeline triggered on all file changes including other tasks | Added `paths: ["task-5-cicd/**"]` to both `push` and `pull_request` triggers |

---

## AI Usage

### Tool Used
Kiro (AI-powered development environment) was used throughout this assessment.

### Purpose
- Generating initial boilerplate for Kubernetes manifests, Nginx config, and pipeline structure
- Reviewing backup script error handling and bash best practices
- Cross-referencing documentation for Trivy flags, GitHub OIDC setup, and S3 Lifecycle Policy schema
- Structuring and improving documentation across all README files

### Manual Review and Modifications
- Kubernetes resource limits chosen based on nginx workload characteristics
- Nginx proxy timeout values reviewed against official documentation
- Dockerfile entry point and layer ordering verified against actual app structure
- Backup script `set -euo pipefail`, validation functions reviewed line by line
- CI/CD `paths` filter, `outputs` between jobs, and health check retry loop written and verified manually
- OIDC trust policy JSON cross-referenced against AWS documentation

### Validation
- Kubernetes YAML validated with `kubectl apply --dry-run=client`
- Nginx config validated with `nginx -t` via Docker
- Bash script reviewed with `shellcheck`
- GitHub Actions YAML verified against official schema documentation
