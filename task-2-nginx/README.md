# Task 2 — Nginx Reverse Proxy Configuration

## Overview

Nginx configuration that:
1. Permanently redirects `abc.com` → `www.abc.com` (HTTP 301)
2. Reverse proxies `www.abc.com` to a backend application running on `127.0.0.1:3000`

## Files

| File | Description |
|---|---|
| `nginx.conf` | Complete Nginx configuration with upstream block, redirect, and reverse proxy |

## Configuration Details

| Setting | Value |
|---|---|
| Redirect | `abc.com` → `www.abc.com` (HTTP 301 permanent) |
| Backend | `127.0.0.1:3000` |
| Keepalive connections | `32` |
| Connect timeout | `10s` |
| Send timeout | `30s` |
| Read timeout | `30s` |

### Proxy Headers Set

| Header | Value |
|---|---|
| `Host` | `$host` |
| `X-Real-IP` | `$remote_addr` |
| `X-Forwarded-For` | `$proxy_add_x_forwarded_for` |
| `X-Forwarded-Proto` | `$scheme` |

## Prerequisites

- Nginx 1.24+
- Backend application running on `127.0.0.1:3000`
- DNS records for `abc.com` and `www.abc.com` pointing to this server

## Validate Configuration Syntax

```bash
# If Nginx is installed locally
sudo nginx -t -c /path/to/task-2-nginx/nginx.conf

# Using Docker (no local Nginx needed)
docker run --rm \
  -v "$(pwd)/task-2-nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:latest nginx -t
```

Expected output:
```
nginx: the configuration file ... syntax is ok
nginx: configuration file ... test is successful
```

## Deploy to a Server

```bash
sudo cp task-2-nginx/nginx.conf /etc/nginx/sites-available/abc.com
sudo ln -sf /etc/nginx/sites-available/abc.com /etc/nginx/sites-enabled/abc.com
sudo nginx -t && sudo systemctl reload nginx
```

## Test Expected Behaviour

```bash
# Should return: HTTP 301 Location: http://www.abc.com/
curl -I http://abc.com

# Should follow redirect and proxy to backend
curl -L http://abc.com

# Should proxy directly to 127.0.0.1:3000
curl -v http://www.abc.com
```

| Request | Expected Response |
|---|---|
| `http://abc.com/` | `301 Moved Permanently` → `http://www.abc.com/` |
| `http://abc.com/any/path` | `301` → `http://www.abc.com/any/path` |
| `http://www.abc.com/` | Response from backend on `127.0.0.1:3000` |

## Assumptions

- Backend application runs on the **same host** as Nginx at `127.0.0.1:3000`.
- HTTP only — TLS/SSL is out of scope. For production, add Let's Encrypt or your certificate.
- Both `abc.com` and `www.abc.com` DNS point to this server.
