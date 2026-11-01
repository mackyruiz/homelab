# Homarr

Homarr is the lab dashboard, with native OIDC login through Authentik and Docker container status.

| | |
|---|---|
| Host | VM 107 `yarr` |
| Address / URL | `https://homarr.example.com` (via [Caddy](caddy.md), no forward auth); `http://10.0.0.160:7575` |
| Ports | 7575 |
| Software | `ghcr.io/homarr-labs/homarr:latest` |
| Data | `/opt/yarr/config/homarr` (mounted as `/appdata`) |
| Deployed by | `ansible/playbooks/yarr.yml`: role `yarr_stack`; Authentik provider by `identity.yml` |
| Depends on | [yarr stack](yarr-stack.md), [Authentik](authentik.md), [Caddy](caddy.md) |
| Used by | [Uptime Kuma](uptime-kuma.md) (health check) |

## Purpose

Dashboard for the lab. Homarr is on 7575 and monitors Docker via the mounted socket.

## Configuration

### Files

| Path | What it sets |
|---|---|
| `ansible/roles/yarr_stack/templates/docker-compose.yml.j2` | Container, OIDC environment, socket and data volumes |
| `ansible/roles/yarr_stack/templates/env.j2` | `HOMARR_OIDC_CLIENT_SECRET` and the encryption key in `/opt/yarr/.env` |
| `ansible/roles/yarr_stack/files/homarr-seed-admin-group.js` | Creates the admin group |
| `ansible/roles/yarr_stack/tasks/main.yml` | Runs the seed script after `docker compose up` |
| `ansible/roles/authentik/templates/blueprints/yarr.yaml.j2` | Homarr OIDC provider and application |

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `homarr_port` | `group_vars/yarr/main.yml` | 7575 |
| `homarr_fqdn` | `group_vars/all/main.yml` | `homarr.example.com`; redirect URI `https://homarr.example.com/api/auth/callback/oidc` |
| `authentik_fqdn` | `group_vars/all` | Used for the issuer and logout URLs |
| `sso_admin_group` | `group_vars/all/main.yml` | `lab-admins`; name of the seeded Homarr group |

Container environment: `AUTH_PROVIDERS=oidc,credentials`, issuer `https://auth.example.com/application/o/homarr/`, client ID `homarr`, scope `openid email profile`, `AUTH_OIDC_AUTO_LOGIN=false`, logout redirects to the Authentik end-session URL.

### Secrets

| Vault variable | Vault file | Used for |
|---|---|---|
| `vault_homarr_secret_encryption_key` | `group_vars/yarr/vault.yml` | Homarr's secret encryption key (`openssl rand -hex 32`); see the table in [yarr-stack.md](yarr-stack.md#secrets) |
| `vault_authentik_homarr_client_secret` | `group_vars/identity/vault.yml` | OIDC client secret; the yarr role reads it through `hostvars` of the Authentik host, and the Authentik blueprint uses the same value ([authentik.md](authentik.md)) |

## How it works

- The Docker socket is mounted for container status.
- Homarr places OIDC users into Homarr groups by name from the groups claim. It offers no env var or REST endpoint to create a group, so after `docker compose up` the role runs `files/homarr-seed-admin-group.js` through `docker exec -i homarr node -`. The script creates the group named by `sso_admin_group` (`lab-admins`) with the `admin` permission, and exits with 3 while Homarr's schema is not ready (the task retries).
- Account mapping: `labadmin` (credentials) stays as break-glass; `labuser` is created by the first SSO login and lands in `lab-admins`.
- Homarr is not behind forward auth; Caddy proxies it directly because Homarr does OIDC itself. See [authentik.md](authentik.md#sso-coverage).

## Operations

Deploy: `ansible-playbook playbooks/yarr.yml` from `ansible/` (Authentik side: `identity.yml`).

Verify: `https://homarr.example.com` shows the Authentik login button; Uptime Kuma checks `https://homarr.example.com/api/health/live`.

What a rebuild does not restore: Homarr boards/apps/integrations (back up `/opt/yarr/config/homarr`), and the first-run Homarr onboarding user on a brand-new `/opt/yarr/config/homarr` (restore the directory, or click through onboarding once).

Known gaps:

- Homarr boards, apps and integrations live in `/opt/yarr/config/homarr` and are not rebuilt from code; back that directory up. A brand-new Homarr data directory needs its onboarding user created once.
