# Legacy Collect — Zitadel auth

This repository is a fork of [ZITADEL](https://github.com/zitadel/zitadel) configured as the identity provider for **Legacy Collect**. This README covers running the stack locally with Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- The default host ports below free on your machine

> **Changing ports:** all host ports are defined in `docker-compose.yml`. If a port is already taken, change the **host** side of the mapping (the number before the `:`). The reverse proxy is published as `"8080:80"` under the `proxy` service — change `8080` to use a different port for the Login UI / Console / API. If you change the proxy port you must also update `ZITADEL_EXTERNALPORT`, the `ZITADEL_*URLV2` / `ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_BASEURI` env vars on the `zitadel-api` service, and the OIDC redirect URIs in `scripts/seed-local.sh` so they still match.

### Default ports

| Host port | Service | Purpose |
|-----------|---------|---------|
| **8080** | proxy (Traefik) | Single entry point — Login UI (`/`, `/ui/v2/login`), Console (`/ui/console`) and the Zitadel API (`/api`) |
| **8026** | mailpit | Mailpit web UI — view captured outgoing emails |
| **1026** | mailpit | Mailpit SMTP intake (maps to container port `1025`) |

The `zitadel-api`, `login-app` and `postgres` services are **not** published to the host directly — they are reached through the proxy on `8080` and over the internal Docker network.

## Starting the project

```bash
docker compose up -d
```

This starts the following services:

| Service | Description |
|---------|-------------|
| **proxy** (Traefik) | Reverse proxy routing traffic on port 8080 |
| **zitadel-api** | ZITADEL identity server (v4.13.0) |
| **login-app** | Next.js login UI served at `/ui/v2/login` |
| **postgres** | PostgreSQL 17 database |
| **mailpit** | Local SMTP server + web UI that captures all outgoing mail |
| **seed** | One-shot container that creates the "LegacyCollect" project, OIDC app, a test user, renames the default org and wires up SMTP |

The first startup takes a few minutes while ZITADEL initializes the database and the seed script configures the instance.

## Accessing the application

Once all services are healthy:

- **Login UI**: http://localhost:8080
- **ZITADEL Console** (admin): http://localhost:8080/ui/console
- **Mailpit** (captured emails): http://localhost:8026

### Default admin credentials

| Username | Password |
|----------|----------|
| `zitadel-admin@zitadel.localhost` | `Password1!` |

### Test user credentials

Created by the seed script:

| Username | Password | Note |
|----------|----------|------|
| `test@most.dev` | `MostDev1234!` | Password change required on first login |

Two-factor authentication is **not** enforced (the seed sets `forceMfa=false` on the instance login policy), so no account is prompted to set up 2FA.

## Finding the Client ID for the frontend

The seed script creates an OIDC application called "LegacyCollect Web" and outputs the generated **Client ID** to the Docker logs. You need this Client ID to configure your frontend project.

### Get the Client ID from logs

```bash
docker compose logs seed
```

Look for the line:

```
OIDC Client ID (LegacyCollect Web): <your-client-id>
```

Alternatively, the Client ID is saved to a file inside the `zitadel-bootstrap` volume. You can read it with:

```bash
docker compose exec login-app cat /zitadel/bootstrap/client_id
```

### Configure the frontend

Set the Client ID in your frontend project's `.env` file:

```env
VITE_ZITADEL_CLIENT_ID=<your-client-id>
```

The OIDC issuer URL is: `http://localhost:8080`

## OIDC Application details

The seed script configures the following OIDC settings:

| Setting | Value |
|---------|-------|
| App type | User Agent (SPA) |
| Auth method | None (PKCE) |
| Redirect URI | `http://localhost:5173/callback` |
| Post-logout redirect | `http://localhost:5173` |
| Response type | Authorization Code |
| Access token type | JWT |
| Role assertions | Enabled (access token + ID token) |

## Email / SMTP

The seed configures the instance SMTP provider to point at the bundled **Mailpit** container (`mailpit-auth:1025`, no auth, no TLS). All outgoing mail — verification links, password resets, etc. — is captured by Mailpit instead of being sent externally. Open http://localhost:8026 to read it.

## Stopping the project

```bash
docker compose down
```

To also remove the database volume (full reset — required to re-run the seed):

```bash
docker compose down -v
```

> The seed is idempotent and skips itself if the `LegacyCollect` project already exists, so changes to `scripts/seed-local.sh` only take effect after a `down -v` reset.

## Rebuilding after code changes

If you modify the login app source code:

```bash
docker compose up -d --build login-app
```
