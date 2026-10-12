FROM node:24-alpine AS builder
RUN corepack enable && corepack prepare pnpm@10.30.3 --activate
WORKDIR /app

# Copy workspace config
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml nx.json ./
COPY packages/ packages/
COPY apps/login/ apps/login/
COPY proto/ proto/

# Install all workspace deps (includes buf)
RUN pnpm install --frozen-lockfile

# Generate proto files
RUN cd packages/zitadel-proto && pnpm exec buf generate ../../proto

# Build the client package (skip DTS to avoid issues)
RUN cd packages/zitadel-client && npx tsup --no-dts

# Build the login app
RUN cd apps/login && NEXT_OUTPUT_MODE=standalone npx next build \
    && cp -r public scripts/* .next/standalone/ \
    && cp -r public .next/standalone/apps/login/public \
    && mv .next/standalone/apps/login/server.js .next/standalone/apps/login/next-server.js \
    && cp .next/standalone/server.mjs .next/standalone/apps/login/server.js \
    && cp -r .next/static .next/standalone/apps/login/.next/

# Production image
FROM node:24-alpine
WORKDIR /app
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs && \
    mkdir -p /.env-file && touch /.env-file/.env && chown -R nextjs:nodejs /.env-file

COPY --from=builder --chown=nextjs:nodejs /app/apps/login/.next/standalone ./

USER nextjs
ENV HOSTNAME="::" \
    PORT="3000" \
    NODE_ENV="production" \
    NODE_OPTIONS="--use-openssl-ca --require /app/load-ssl-cert-dir.cjs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    ZITADEL_TLS_ENABLED="false"

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/node", "/app/healthcheck.mjs", "http://localhost:3000/ui/v2/login/ready"]
ENTRYPOINT ["/app/entrypoint.sh", "node", "apps/login/server.js"]
