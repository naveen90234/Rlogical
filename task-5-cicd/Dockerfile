# =============================================================================
# Dockerfile — nodejs-todo-app
# App: Express + SQLite/Postgres todo list (src/index.js, port 3000)
# Base: node:20-alpine (minimal attack surface)
# Pattern: multi-stage build — builder installs all deps, production image
#          carries only runtime deps and source
# =============================================================================

# ─── Stage 1: Builder ─────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copy manifests first — Docker caches this layer until package files change
COPY package.json package-lock.json ./

# Install ALL dependencies (including devDependencies) for any build/test step
RUN npm ci --frozen-lockfile

# Copy application source
COPY src/ ./src/


# ─── Stage 2: Production ──────────────────────────────────────────────────────
FROM node:20-alpine AS production

# Create a non-root user — never run as root inside a container
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Install ONLY production dependencies in the final image
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile --omit=dev && \
    npm cache clean --force

# Copy application source from the builder stage
COPY --from=builder /app/src ./src/

# Fix ownership so the non-root user can read/write the app files
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose the application port
EXPOSE 3000

# Health check — verifies the Express server is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:3000/ || exit 1

# Start the application
CMD ["node", "src/index.js"]
