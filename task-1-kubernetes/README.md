# Task 1 — Kubernetes Deployment

## Overview

Kubernetes manifests to deploy an NGINX application with production-grade configuration including health probes, resource management, and rolling updates.

## Files

| File | Description |
|---|---|
| `deployment.yaml` | Deploys `nginx:latest` with 2 replicas, RollingUpdate strategy, readiness/liveness probes, CPU and memory limits |
| `service.yaml` | ClusterIP Service exposing NGINX internally on port 80 |

## Deployment Configuration

| Setting | Value |
|---|---|
| Image | `nginx:latest` |
| Replicas | `2` |
| Strategy | `RollingUpdate` (maxSurge: 1, maxUnavailable: 0) |
| CPU Request | `100m` |
| CPU Limit | `250m` |
| Memory Request | `128Mi` |
| Memory Limit | `256Mi` |
| Container Port | `80` |

## Health Probes

| Probe | Type | Path | Initial Delay | Period |
|---|---|---|---|---|
| Readiness | HTTP GET | `/` on port 80 | 5s | 10s |
| Liveness | HTTP GET | `/` on port 80 | 10s | 15s |

## Service Configuration

| Setting | Value |
|---|---|
| Type | `ClusterIP` |
| Port | `80` |
| Target Port | `80` |
| Selector | `app: nginx` |

## Prerequisites

- `kubectl` v1.28+
- A running Kubernetes cluster (minikube, k3d, EKS, GKE, AKS, or kubeadm)

## Commands

### Apply Manifests

```bash
kubectl apply -f task-1-kubernetes/deployment.yaml
kubectl apply -f task-1-kubernetes/service.yaml
```

### Verify Deployment

```bash
kubectl rollout status deployment/nginx-deployment
kubectl get deployment nginx-deployment
```

### Verify Pods

```bash
kubectl get pods -l app=nginx
kubectl describe pod -l app=nginx
```

### Verify Service

```bash
kubectl get service nginx-service
kubectl get endpoints nginx-service
```

### Confirm Application is Accessible Through the Service

```bash
# Port-forward to test locally
kubectl port-forward service/nginx-service 8080:80

# In a separate terminal
curl http://localhost:8080
# Expected: nginx default welcome page (HTTP 200)
```

### Dry-Run Validation (no cluster needed)

```bash
kubectl apply --dry-run=client -f task-1-kubernetes/deployment.yaml
kubectl apply --dry-run=client -f task-1-kubernetes/service.yaml
```

### Clean Up

```bash
kubectl delete -f task-1-kubernetes/deployment.yaml
kubectl delete -f task-1-kubernetes/service.yaml
```

## Assumptions

- `nginx:latest` is accessible from the cluster nodes (public internet or private registry mirror).
- Resource values are appropriate for a basic NGINX workload and may need tuning for production traffic.
- The `ClusterIP` service type exposes NGINX only within the cluster. For external access, change the type to `NodePort` or `LoadBalancer`.
