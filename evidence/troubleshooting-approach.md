# Task 6 — Troubleshooting and Operational Approach

---

## Scenario A — Kubernetes Pod: STATUS Running, READY 0/1

### What This Means
The Pod process is alive (the container started), but it has not passed its readiness probe. Kubernetes has removed it from the Service endpoints, so no traffic is being routed to it.

---

### Step 1 — Describe the Pod

**Why:** `kubectl describe pod` gives the most complete picture — events, probe results, container state, environment variables, and volume mounts — in a single command.

```bash
kubectl describe pod <pod-name> -n <namespace>
```

**What to look for:**
- `Conditions` section: `Ready: False` confirms the readiness probe is failing.
- `Events` section: Look for `Readiness probe failed` messages with the HTTP response code or connection error.
- `Last State` / `Restart Count`: If the container has restarted, the readiness failure may be caused by a crash loop.

---

### Step 2 — Check Pod Logs

**Why:** The application itself may be logging the reason it is not ready (e.g. failed DB connection, missing config, port binding error).

```bash
# Current logs
kubectl logs <pod-name> -n <namespace>

# If the container previously crashed, check prior instance logs
kubectl logs <pod-name> -n <namespace> --previous
```

**What to look for:**
- Startup errors (uncaught exceptions, missing environment variables)
- Port binding failures (`EADDRINUSE`, `EACCES`)
- Database or service connection failures at boot
- Application-level health endpoint returning non-2xx

---

### Step 3 — Verify the Readiness Probe Configuration

**Why:** The probe may be misconfigured — wrong path, wrong port, or `initialDelaySeconds` too short for the application to start.

```bash
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 15 readinessProbe
```

**What to check:**
- `httpGet.path` — does this endpoint exist in the application?
- `httpGet.port` — does this match the container's `containerPort`?
- `initialDelaySeconds` — is it long enough for the app to start?
- `failureThreshold` — how many consecutive failures before marked not ready?

**Quick test — exec into the Pod and hit the probe endpoint directly:**

```bash
kubectl exec -it <pod-name> -n <namespace> -- wget -qO- http://localhost:<port><path>
# or
kubectl exec -it <pod-name> -n <namespace> -- curl -v http://localhost:<port><path>
```

---

### Step 4 — Check Events at Namespace Level

**Why:** Broader events may reveal resource pressure, image pull failures, or scheduling issues.

```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
```

---

### Step 5 — Check Resource Constraints

**Why:** If the node is under memory pressure, the OOM killer may be terminating the process before it becomes ready.

```bash
kubectl top pod <pod-name> -n <namespace>
kubectl top nodes
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

---

### Resolution Decision Tree

```
Readiness probe failing
├── Application logs show startup error
│   └── Fix application config (env vars, secrets, DB connectivity)
├── Probe path/port misconfigured
│   └── Correct the readinessProbe in deployment.yaml
├── initialDelaySeconds too short
│   └── Increase initialDelaySeconds to allow app startup time
├── OOMKilled
│   └── Increase memory limits/requests in deployment.yaml
└── Application healthy but probe path returns non-2xx
    └── Fix the health endpoint in the application code
```

---
---

## Scenario B — Pods Running but Application Not Accessible Through the Service

### What This Means
The Pods are healthy, but traffic cannot reach the application via the Service. This is almost always a label/selector mismatch, a port mapping error, or a network policy restriction.

---

### Step 1 — Verify the Service Configuration

**Why:** Confirm the Service exists, is the right type, and is listening on the expected port.

```bash
kubectl get service <service-name> -n <namespace>
kubectl describe service <service-name> -n <namespace>
```

**What to look for in `describe`:**
- `Selector` — must match the Pod labels exactly.
- `Endpoints` — if this shows `<none>`, the selector is not matching any Pods.
- `Port` / `TargetPort` — `port` is what clients connect to; `targetPort` must match the container's `containerPort`.

---

### Step 2 — Check Service Endpoints

**Why:** If `Endpoints` is `<none>`, Kubernetes has not found any Pods matching the selector. This is the most common cause.

```bash
kubectl get endpoints <service-name> -n <namespace>
```

**Expected output (healthy):**
```
NAME            ENDPOINTS           AGE
nginx-service   10.0.0.5:80,...    5m
```

**If endpoints are empty — compare labels:**

```bash
# What labels does the Service selector expect?
kubectl get service <service-name> -n <namespace> -o jsonpath='{.spec.selector}'

# What labels do the Pods actually have?
kubectl get pods -n <namespace> --show-labels
```

A single typo (e.g. `app: ngnix` vs `app: nginx`) causes zero endpoints.

---

### Step 3 — Test Connectivity Directly to a Pod (Bypass Service)

**Why:** Isolates whether the problem is the application itself or the Service routing layer.

```bash
# Get Pod IP
kubectl get pod <pod-name> -n <namespace> -o wide

# Test from another Pod in the same namespace
kubectl run debug --image=busybox --restart=Never -it --rm \
  -- wget -qO- http://<pod-ip>:<container-port>
```

If this works → the application is fine, the Service is the problem.  
If this fails → the application is not responding on the expected port.

---

### Step 4 — Test the Service ClusterIP Directly

```bash
# Get the ClusterIP
kubectl get service <service-name> -n <namespace>

# Test from within the cluster
kubectl run debug --image=busybox --restart=Never -it --rm \
  -- wget -qO- http://<cluster-ip>:<service-port>
```

---

### Step 5 — Check for NetworkPolicy Restrictions

**Why:** A NetworkPolicy may be blocking traffic to the Pods even though the Service is configured correctly.

```bash
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <policy-name> -n <namespace>
```

Check that the `podSelector` and `ingress` rules allow traffic from the expected source on the expected port.

---

### Step 6 — For NodePort / LoadBalancer Services

```bash
# NodePort — check the node's firewall/security group allows the NodePort range (30000-32767)
kubectl get service <service-name> -n <namespace> -o jsonpath='{.spec.ports[*].nodePort}'

# LoadBalancer — check the external IP is assigned and the cloud load balancer is healthy
kubectl get service <service-name> -n <namespace> -w
```

---

### Resolution Decision Tree

```
No access through Service
├── Endpoints: <none>
│   └── Label/selector mismatch → fix labels in deployment.yaml or selector in service.yaml
├── Endpoints populated but no response
│   ├── Wrong targetPort → match targetPort to containerPort
│   └── Application not listening on expected port → check app config
├── NetworkPolicy blocking traffic
│   └── Add or update ingress rule to allow traffic
└── NodePort/LoadBalancer not reachable externally
    └── Check cloud security group / firewall rules
```

---
---

## Scenario C — Nginx Returns 502 Bad Gateway

### What This Means
Nginx is running and accepted the request, but it could not get a valid response from the upstream backend (the application on port 3000). 502 means the upstream connection failed or returned garbage.

---

### Step 1 — Check Nginx Error Logs

**Why:** Nginx logs the specific upstream error that caused the 502.

```bash
sudo tail -100 /var/log/nginx/error.log
# or for a specific vhost
sudo tail -100 /var/log/nginx/www.abc.com.error.log
```

**Common error messages and meanings:**

| Error Message | Meaning |
|---|---|
| `connect() failed (111: Connection refused)` | Nothing is listening on port 3000 |
| `connect() failed (110: Connection timed out)` | Port 3000 is firewalled or app is hung |
| `no live upstreams while connecting to upstream` | All upstream servers are down |
| `recv() failed (104: Connection reset by peer)` | App crashed mid-request |

---

### Step 2 — Check if the Application is Running

**Why:** The most common cause of 502 is that the backend process has stopped.

```bash
# Check if any process is listening on port 3000
sudo ss -tlnp | grep 3000
# or
sudo netstat -tlnp | grep 3000

# Check Node.js process directly
ps aux | grep node

# If managed by systemd
sudo systemctl status <app-service-name>
sudo journalctl -u <app-service-name> -n 50 --no-pager
```

**If the process is not running — start it:**

```bash
sudo systemctl start <app-service-name>
# or for a Docker container
docker ps -a | grep nodejs-app
docker start nodejs-app
```

---

### Step 3 — Test the Backend Directly (Bypass Nginx)

**Why:** Confirms whether the issue is the application or Nginx's proxy configuration.

```bash
curl -v http://127.0.0.1:3000/
```

- `200 OK` → Application is fine; issue is in Nginx config.
- `Connection refused` → Application is not listening on port 3000.
- `Timeout` → Application is running but not responding (deadlock, high load).

---

### Step 4 — Validate Nginx Configuration

**Why:** A misconfigured `proxy_pass` URL (wrong port, trailing slash issues) causes 502.

```bash
# Test syntax
sudo nginx -t

# Check the proxy_pass directive
sudo grep -n proxy_pass /etc/nginx/sites-enabled/abc.com
# Expected: proxy_pass http://127.0.0.1:3000;
```

---

### Step 5 — Check System Resources

**Why:** If the server is under memory pressure, the OS may be OOM-killing the application process.

```bash
# Check recent OOM kills
sudo dmesg | grep -i "killed process" | tail -20

# Current memory usage
free -h

# Check if app process was restarted unexpectedly
sudo journalctl -u <app-service-name> --since "1 hour ago" | grep -i "killed\|error\|failed"
```

---

### Step 6 — Check SELinux / AppArmor (if applicable)

```bash
# SELinux
getenforce
sudo audit2why < /var/log/audit/audit.log | grep nginx

# AppArmor
sudo aa-status
sudo journalctl -k | grep apparmor | tail -20
```

---

### Resolution Decision Tree

```
502 Bad Gateway
├── error.log: "Connection refused" on port 3000
│   ├── App process stopped → start/restart the service
│   └── App listening on different port → update proxy_pass in nginx.conf
├── error.log: "Connection timed out"
│   ├── Firewall blocking loopback traffic → check iptables/ufw rules
│   └── App hung → restart the service, investigate app logs
├── curl 127.0.0.1:3000 works but Nginx returns 502
│   └── proxy_pass misconfigured → fix nginx.conf, reload nginx
└── App crashes immediately after start
    └── Check app logs / journalctl for startup errors
```

---
---

## Scenario D — Ubuntu Production Server Slow, Application Not Responding

### Approach: Triage in Order of Impact — CPU → Memory → Disk → Process → Network

---

### Step 1 — Get an Immediate Overview

```bash
# Uptime + load average (1, 5, 15 min)
uptime

# Top 10 CPU and memory consumers right now
top -b -n 1 | head -30
# or more readable:
htop
```

**Load average interpretation:** If load average > number of CPU cores, the system is overloaded.

```bash
# Number of CPU cores
nproc
```

---

### Step 2 — CPU Investigation

```bash
# Identify CPU-hungry processes
ps aux --sort=-%cpu | head -15

# Check for runaway processes or kernel threads consuming CPU
top -b -n 1 -H   # thread-level view

# CPU usage breakdown (user/system/iowait)
vmstat 2 5
# High 'wa' (iowait) → disk I/O bottleneck, not pure CPU
```

**Resolution options:**
- Runaway app process → restart the service
- High iowait → investigate disk (see Step 4)
- Kernel process consuming CPU → check `dmesg` for hardware errors

---

### Step 3 — Memory Investigation

```bash
# Memory overview
free -h

# Swap usage — heavy swap means RAM exhaustion
swapon --show
vmstat -s | grep -i swap

# Processes consuming the most memory
ps aux --sort=-%mem | head -15

# Check for OOM kills in the last hour
sudo dmesg | grep -i "out of memory\|oom\|killed process" | tail -20
sudo journalctl -k --since "1 hour ago" | grep -i oom
```

**If memory is exhausted:**
```bash
# Temporary relief — clear page cache (safe on production, does not affect running processes)
sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches

# Restart the application if it has a memory leak
sudo systemctl restart <app-service-name>
```

---

### Step 4 — Disk Space and I/O Investigation

```bash
# Disk space — check all mount points
df -h

# Find largest directories (useful if disk is full)
sudo du -sh /* 2>/dev/null | sort -rh | head -10
sudo du -sh /var/log/* | sort -rh | head -10

# Real-time disk I/O
iostat -xz 2 5
# High %util or high await → disk is saturated

# Which processes are doing the most I/O
sudo iotop -o -b -n 3

# Check for a full disk causing app failures
sudo find /var/log -name "*.log" -size +500M
```

**Common causes of full disk:**
- Unbounded application logs → rotate or truncate: `sudo truncate -s 0 /var/log/<app>.log`
- Large core dump files: `sudo find / -name "core.*" -size +100M`
- Docker overlay storage: `docker system df` → `docker system prune`

---

### Step 5 — Application Process and Service Status

```bash
# Is the application service running?
sudo systemctl status <app-service-name>

# Recent service events
sudo journalctl -u <app-service-name> -n 100 --no-pager

# Is the app process actually alive?
ps aux | grep node

# Is the app listening on its expected port?
sudo ss -tlnp | grep 3000

# Test the app directly, bypassing any load balancer
curl -v --max-time 5 http://127.0.0.1:3000/
```

---

### Step 6 — Network Investigation

```bash
# Current connections — check for connection exhaustion
ss -s

# Established connections to the app port
ss -tnp | grep :3000 | wc -l

# Check for too many TIME_WAIT connections (indicates connection leak)
ss -tan | grep TIME_WAIT | wc -l

# Network interface errors
ip -s link

# Check for packet loss to key services (e.g. database)
ping -c 10 <database-host>

# DNS resolution time (slow DNS can make app appear unresponsive)
time nslookup <external-dependency-hostname>
```

---

### Step 7 — Application Logs

```bash
# Application logs (adjust path to your app)
sudo tail -200 /var/log/<app-name>/app.log
sudo journalctl -u <app-service-name> --since "30 minutes ago" --no-pager

# Look for specific patterns
sudo journalctl -u <app-service-name> --since "1 hour ago" \
  | grep -iE "error|exception|fatal|timeout|refused|heap|memory"
```

---

### Step 8 — File Permissions

```bash
# Check the app directory permissions
ls -la /opt/<app-name>/

# Check log directory writability
sudo -u <app-user> touch /var/log/<app-name>/test && echo "Writable" || echo "Permission denied"

# Check for recently changed files (potential deployment issue)
find /opt/<app-name> -newer /opt/<app-name>/package.json -type f | head -20
```

---

### Summary: Investigation Order and Quick Reference

| Priority | Area | Key Commands |
|---|---|---|
| 1 | Load overview | `uptime`, `top`, `htop` |
| 2 | CPU | `ps aux --sort=-%cpu`, `vmstat 2 5` |
| 3 | Memory | `free -h`, `dmesg \| grep oom` |
| 4 | Disk space | `df -h`, `du -sh /var/log/*` |
| 5 | Disk I/O | `iostat -xz 2 5`, `iotop -o` |
| 6 | App process | `systemctl status`, `ss -tlnp \| grep 3000` |
| 7 | App logs | `journalctl -u <service> -n 100` |
| 8 | Network | `ss -s`, `ping`, `curl 127.0.0.1:3000` |
| 9 | File permissions | `ls -la`, `find` recent changes |
