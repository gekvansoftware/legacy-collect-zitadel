# =============================================================================
# Stage 1: Get the ZITADEL binary from the official image
# =============================================================================
FROM ghcr.io/zitadel/zitadel:v4.13.0 AS zitadel-bin

# =============================================================================
# Stage 2: Build the Next.js login app
# =============================================================================
FROM node:24-alpine AS login-builder

RUN corepack enable && corepack prepare pnpm@10.30.3 --activate
WORKDIR /app

# Copy workspace config
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml nx.json ./
COPY packages/ packages/
COPY apps/login/ apps/login/
COPY proto/ proto/

# Install all workspace deps
RUN pnpm install --frozen-lockfile

# Generate proto files
RUN cd packages/zitadel-proto && pnpm exec buf generate ../../proto

# Build the client package
RUN cd packages/zitadel-client && npx tsup --no-dts

# Build the login app
RUN cd apps/login && NEXT_OUTPUT_MODE=standalone npx next build \
    && cp -r public scripts/* .next/standalone/ \
    && cp -r public .next/standalone/apps/login/public \
    && mv .next/standalone/apps/login/server.js .next/standalone/apps/login/next-server.js \
    && cp .next/standalone/server.mjs .next/standalone/apps/login/server.js \
    && cp -r .next/static .next/standalone/apps/login/.next/

# =============================================================================
# Stage 3: Final combined image
# =============================================================================
FROM node:24-alpine AS final

RUN apk add --no-cache ca-certificates

# Create user
RUN addgroup --system --gid 1001 zitadel && \
    adduser --system --uid 1001 --ingroup zitadel zitadel

# Copy ZITADEL binary from official image
COPY --from=zitadel-bin /app/zitadel /app/zitadel
RUN chmod +x /app/zitadel

# Copy login app
COPY --from=login-builder /app/apps/login/.next/standalone /app/login/

# Copy entrypoint scripts
COPY apps/login/scripts/entrypoint.sh /app/entrypoint-login.sh
RUN chmod +x /app/entrypoint-login.sh

# Create env-file directory for login app
RUN mkdir -p /.env-file && touch /.env-file/.env && chown -R zitadel:zitadel /.env-file

# Create tmp directory for bootstrap files (PAT tokens, etc.)
RUN mkdir -p /tmp/zitadel && chown -R zitadel:zitadel /tmp/zitadel

# Combined entrypoint
COPY <<'EOF' /app/start.sh
#!/bin/sh
# Start login app in background
/app/entrypoint-login.sh node /app/login/apps/login/server.js &

# Run ZITADEL as PID 1
exec /app/zitadel "$@"
EOF
RUN chmod +x /app/start.sh

WORKDIR /app
USER zitadel

ENV HOSTNAME="0.0.0.0" \
    PORT="3000" \
    NODE_ENV="production" \
    NODE_OPTIONS="--use-openssl-ca --require /app/login/load-ssl-cert-dir.cjs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    ZITADEL_TLS_ENABLED="false"

EXPOSE 8080 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD ["/app/zitadel", "ready"]

ENTRYPOINT ["/app/start.sh"]
CMD ["start-from-init"]
