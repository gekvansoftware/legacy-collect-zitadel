# Local Development with Docker

This guide explains how to run the Legacy Collect login application locally using Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- Ports `8080` and `8081` available on your machine

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
| **seed** | One-shot container that creates the "LegacyCollect" project, OIDC app, and a test user |

The first startup takes a few minutes while ZITADEL initializes the database and the seed script configures the project.

## Accessing the application

Once all services are healthy:

- **Login UI**: http://localhost:8080
- **ZITADEL Console** (admin): http://localhost:8080/ui/console

### Default admin credentials

| Username | Password |
|----------|----------|
| `zitadel-admin@zitadel.localhost` | `Password1!` |

### Test user credentials

Created by the seed script:

| Username | Password | Note |
|----------|----------|------|
| `test@most.dev` | `MostDev1234!` | Password change required on first login |

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

## Stopping the project

```bash
docker compose down
```

To also remove the database volume (full reset):

```bash
docker compose down -v
```

## Rebuilding after code changes

If you modify the login app source code:

```bash
docker compose up -d --build login-app
```
