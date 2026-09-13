# Evidence Directory

This directory contains testing evidence, command outputs, and validation results for the DevOps Practical Assessment.

---

## Structure

```
evidence/
├── README.md                    ← This file
├── troubleshooting-approach.md  ← Task 6: All four troubleshooting scenarios
└── test-evidence/               ← Screenshots, command outputs, logs
    ├── task1-kubernetes/        ← kubectl outputs
    ├── task2-nginx/             ← nginx -t output, curl test results
    ├── task3-docker/            ← docker build/run outputs
    ├── task4-backup/            ← backup script dry-run output
    └── task5-cicd/              ← Pipeline screenshots or run logs
```

---

## What Was Tested Locally

### Task 1 — Kubernetes
- YAML validated with `kubectl apply --dry-run=client -f deployment.yaml`
- YAML validated with `kubectl apply --dry-run=client -f service.yaml`
- Manifest syntax verified with `yamllint`

**Could not execute:** Live cluster apply requires a running Kubernetes cluster (minikube / kind / cloud).  
**How to validate in a real environment:** See root README — Task 1 validation section.

---

### Task 2 — Nginx
- Configuration syntax validated with `nginx -t` (requires nginx installed locally or in Docker)
- Reverse proxy logic reviewed manually against Nginx documentation
- 301 redirect logic confirmed by reviewing `return 301` directive behaviour

**Quick local test using Docker:**
```bash
docker run --rm -v $(pwd)/task-2-nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro nginx:latest nginx -t
```

---

### Task 3 — Docker
- Dockerfile linted using `hadolint`
- Multi-stage build structure reviewed
- `.dockerignore` reviewed to confirm node_modules and secrets are excluded

**Build and run (requires Docker):**
```bash
cd task-3-docker
docker build -t nodejs-app:test .
docker run -d -p 3000:3000 --name nodejs-app-test nodejs-app:test
docker ps
docker logs nodejs-app-test
docker stop nodejs-app-test && docker rm nodejs-app-test
```

---

### Task 4 — Backup Script
- Script linted with `shellcheck backup.sh`
- Error handling paths reviewed manually
- Environment variable validation logic tested with missing variables
- AWS CLI commands reviewed against official documentation

**Could not execute end-to-end:** Requires a running MySQL instance and AWS S3 bucket with IAM Role.  
**How to validate:** See root README — Task 4 validation section.

---

### Task 5 — CI/CD Pipeline
- YAML syntax validated with `yamllint github-actions.yml`
- Pipeline logic reviewed stage by stage
- OIDC configuration reviewed against AWS and GitHub documentation
- Trivy exit-code behaviour confirmed from Trivy documentation

**Could not execute:** Requires a GitHub repository, SonarQube instance, AWS ECR, and EC2 server.  
**How to validate:** Push to a repository with the required secrets configured and observe the Actions run.

---

## What Could Not Be Executed and Why

| Component | Reason | How to Validate When Infrastructure Is Available |
|---|---|---|
| kubectl apply | No Kubernetes cluster available locally | `kubectl apply -f task-1-kubernetes/` against minikube or a cloud cluster |
| Nginx live test | No domain DNS for abc.com / www.abc.com | Test with `/etc/hosts` entries pointing to a local nginx instance |
| Docker full build | Requires a real Node.js app in `src/` | Place a minimal `src/index.js` and run `docker build` |
| MySQL backup | Requires MySQL server + S3 bucket + IAM Role | Run on an Ubuntu EC2 instance with the environment variables set |
| GitHub Actions | Requires GitHub repository + all secrets | Push to GitHub with secrets configured; monitor the Actions tab |
| ECR push | Requires AWS account + ECR repository | Configure OIDC and `AWS_ROLE_ARN` secret; re-run the pipeline |
| EC2 deploy | Requires a running EC2 instance | Configure `EC2_HOST`, `EC2_USER`, `EC2_SSH_PRIVATE_KEY` secrets |

---

## Security Note

No credentials, tokens, private keys, IP addresses, or sensitive infrastructure details are included in this evidence directory. All values shown in examples are placeholders.
