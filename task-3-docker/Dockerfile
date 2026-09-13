# ─────────────────────────────────────────────────────────────
# Stage 1: Builder — install ALL dependencies (including devDeps)
# so that any build/compile step can run.
# ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy dependency manifests first for Docker layer caching.
# Re-run npm ci only when package files change, not on every source change.
COPY package.json package-lock.json ./

# Install all dependencies (including devDependencies needed for build)
RUN npm ci --frozen-lockfile

# Copy application source code
COPY src/ ./src/

# If the project has a build step (e.g. TypeScript compile, bundling), run it here.
# Remove or adjust if not applicable.
# RUN npm run build


# ─────────────────────────────────────────────────────────────
# Stage 2: Production image — lean runtime image
# ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS production

# Create a non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory
WORKDIR /app

# Copy dependency manifests and install ONLY production dependencies
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile --omit=dev && \
    npm cache clean --force

# Copy built application from builder stage
# If you have a build step, replace src/ with dist/ or your output dir
COPY --from=builder /app/src ./src/

# Change ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 3000

# Health check to verify the app is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/ || exit 1

# Start the application
# Adjust the entry point to match your project (e.g. src/index.js, src/server.js, dist/index.js)
CMD ["node", "src/index.js"]
