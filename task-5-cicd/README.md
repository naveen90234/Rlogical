# Task 5 — GitHub Actions CI/CD Pipeline

## Overview

The pipeline is defined in `github-actions.yml` and implements a 7-stage CI/CD workflow for a Node.js application. It triggers on pushes and pull requests to `main` and `develop` branches.

---

## Pipeline Stages

| Stage | Name | Description |
|---|---|---|
| 1 | App Preparation | Checkout, Node.js setup, `npm ci`, run tests |
| 2 | Code Quality | SonarQube static analysis + Quality Gate |
| 3 | Docker Build | Build image, tag with short Git SHA, cache layers |
| 4 | Security Scan | Trivy scan — fails on HIGH/CRITICAL vulnerabilities |
| 5 | Push to ECR | Authenticate via OIDC, push to AWS ECR |
| 6 | Deploy to EC2 | SSH into EC2, pull image, restart container |
| 7 | Health Check | HTTP check with retries against deployed app |

Stages 5–7 run **only on pushes to `main`**, not on pull requests.

---

## Required GitHub Actions Secrets

Configure these under **Settings → Secrets and variables → Actions** in your GitHub repository. Never commit these values.

| Secret Name | Description |
|---|---|
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `AWS_ROLE_ARN` | ARN of the IAM Role for OIDC federation (e.g. `arn:aws:iam::123456789:role/github-actions-role`) |
| `ECR_REPOSITORY` | ECR repository name (e.g. `nodejs-app`) |
| `EC2_HOST` | Public IP or DNS of the EC2 deployment server |
| `EC2_USER` | SSH username (e.g. `ubuntu`) |
| `EC2_SSH_PRIVATE_KEY` | PEM-format private key for SSH access to EC2 |
| `SONAR_TOKEN` | SonarQube authentication token |
| `SONAR_HOST_URL` | SonarQube server URL (e.g. `https://sonar.yourcompany.com`) |

---

## AWS Authentication — OIDC (No Long-Lived Keys)

The pipeline uses **GitHub OIDC federation** instead of storing AWS Access Key / Secret Key as secrets. This is the recommended AWS approach.

### Setup Steps

1. **Create an OIDC identity provider in IAM:**
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. **Create an IAM Role** with a trust policy for your repository:

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

3. **Attach the following permissions** to the IAM Role:
   - `AmazonEC2ContainerRegistryPowerUser` — for ECR push
   - `ecr:GetAuthorizationToken` — for ECR login

4. **Store the Role ARN** as the `AWS_ROLE_ARN` secret.

---

## Vulnerability Handling — Trivy (Stage 4)

### Pipeline Behaviour
- `exit-code: "1"` — pipeline **fails** if HIGH or CRITICAL vulnerabilities are found.
- `ignore-unfixed: true` — vulnerabilities with no available fix are ignored to avoid blocking on issues outside your control.
- Scan results are uploaded as a pipeline artifact (`trivy-scan-results`) and retained for 7 days.

### Assumptions

| Area | Assumption |
|---|---|
| Base image | `node:20-alpine` is used to minimise surface area. Some OS-level CVEs may exist with no upstream fix — these are excluded via `ignore-unfixed: true`. |
| Dependencies | Application `npm` dependencies are scanned. Developers are responsible for keeping dependencies up to date. |
| Accepted risk | If a HIGH/CRITICAL CVE has no fix available and blocks the pipeline, it can be suppressed via a `.trivyignore` file with documented justification. |
| Production | In production, consider adding `--exit-code 0` for MEDIUM and below, and alerting only (not blocking) on MEDIUM vulnerabilities. |

### Adding Vulnerability Exceptions

Create a `.trivyignore` file in the repository root:

```
# Format: CVE-ID (one per line)
# Add a comment explaining why this is accepted
CVE-2023-XXXXX  # No fix available — base image vendor tracking
```

---

## Image Tagging Strategy

| Tag | Value | Used For |
|---|---|---|
| Short SHA | `a1b2c3d` | Unique, traceable per-commit identifier |
| `latest` | Always updated | Convenience tag for pulling most recent build |

The short SHA tag is generated as `${GITHUB_SHA::7}` and passed between jobs via `outputs`.

---

## EC2 Deployment Details

- The deploy job SSHs into the EC2 instance using the `appleboy/ssh-action`.
- It authenticates Docker to ECR using `aws ecr get-login-password`.
- It stops and removes the existing container before starting the new one.
- The container runs with `--restart unless-stopped` to survive server reboots.
- Port `3000` is mapped to the host.

### EC2 Prerequisites

The EC2 instance must have:
- Docker installed and running
- AWS CLI installed
- An IAM Instance Profile with `ecr:GetAuthorizationToken` and `ecr:BatchGetImage` permissions
- Port 3000 open in the Security Group (for the health check)
- The SSH public key of `EC2_SSH_PRIVATE_KEY` in `~/.ssh/authorized_keys`

---

## Pipeline Trigger Behaviour

| Event | Stages Run |
|---|---|
| PR to `main` | Stages 1–4 (prepare, quality, build, scan) |
| Push to `main` | All stages 1–7 |
| Push to `develop` | Stages 1–4 |

---

## Assumptions

- The Node.js application entry point is `src/index.js`. Adjust `CMD` in the Dockerfile if different.
- SonarQube is self-hosted or SonarCloud. The `SONAR_HOST_URL` secret handles both.
- The EC2 instance is a single server (no load balancer). For HA deployments, replace the SSH deploy step with ECS, EKS, or an ASG rolling update.
- The application exposes a root path (`/`) that returns a 2xx response for the health check.
