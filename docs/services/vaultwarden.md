# Vaultwarden

Self-hosted Bitwarden-compatible password manager at `https://vault.example.com`, with an optional Authentik SSO login.

| | |
|---|---|
| Host | VM 303 `vaultwarden` (identity VM, see [proxmox.md](proxmox.md)) |
| Address / URL | 10.0.0.33:8000; `https://vault.example.com` via [Caddy](caddy.md) |
| Ports | 8000/tcp (published to container port 80) |
| Software | `vaultwarden/server:1.37.4` |
| Data | `/opt/vaultwarden/data` |
| Deployed by | `ansible/playbooks/identity.yml`, role `vaultwarden` (host roles: [host-baseline.md](host-baseline.md)) |
| Depends on | [authentik.md](authentik.md) (optional SSO login), [caddy.md](caddy.md) (HTTPS name), [freeipa.md](freeipa.md) (host enrolment) |
| Used by | People; no other lab service reads from it |

## Purpose

Stores the lab's passwords. Signups are disabled and invitations are enabled, so accounts are created by invitation only. The vault stays usable when Authentik or FreeIPA is down, because SSO is an extra login option and the master-password login stays on.

## Configuration

### Files

| Path | What it sets |
|---|---|
| [`ansible/roles/vaultwarden/defaults/main.yml`](../../ansible/roles/vaultwarden/defaults/main.yml) | `vaultwarden_dir` and `vaultwarden_tag` |
| [`ansible/roles/vaultwarden/tasks/main.yml`](../../ansible/roles/vaultwarden/tasks/main.yml) | Creates the directories, renders `.env` (mode 0600) and the compose file, starts the project, waits for `/alive` |
| [`ansible/roles/vaultwarden/templates/env.j2`](../../ansible/roles/vaultwarden/templates/env.j2) | Application settings (below) |
| [`ansible/roles/vaultwarden/templates/docker-compose.yml.j2`](../../ansible/roles/vaultwarden/templates/docker-compose.yml.j2) | Container `vaultwarden`, port `8000:80`, `./data:/data`, `restart: unless-stopped` |
| [`ansible/inventory/group_vars/vaultwarden_servers/main.yml`](../../ansible/inventory/group_vars/vaultwarden_servers/main.yml) | UFW opens 22 and the Vaultwarden port |
| [`ansible/roles/authentik/templates/blueprints/homelab.yaml.j2`](../../ansible/roles/authentik/templates/blueprints/homelab.yaml.j2) | The Authentik side: OIDC provider for Vaultwarden and the "Vaultwarden: email (verified)" scope mapping |

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `vaultwarden_dir` | role defaults | `/opt/vaultwarden` |
| `vaultwarden_tag` | role defaults | `1.37.4` |
| `vaultwarden_fqdn` | `group_vars/identity/main.yml` | `vault.example.com`; becomes `DOMAIN` |
| `vaultwarden_http_port` | `group_vars/identity/main.yml` | `8000` |
| `authentik_fqdn` | `group_vars/all/main.yml` | `auth.example.com`; builds `SSO_AUTHORITY` |

Settings in `.env`:

- `SIGNUPS_ALLOWED=false`, `INVITATIONS_ALLOWED=true`, `SHOW_PASSWORD_HINT=false`.
- `ADMIN_TOKEN` is the argon hash from the vault.
- `SSO_ENABLED=true`, `SSO_ONLY=false`.
- `SSO_AUTHORITY=https://auth.example.com/application/o/vaultwarden/`, `SSO_SCOPES=openid profile email offline_access`, `SSO_CLIENT_ID=vaultwarden`.

### Secrets

All in `ansible/inventory/group_vars/identity/vault.yml`.

| Vault variable | Vault file | Used for |
|---|---|---|
| `vault_vaultwarden_admin_token_hash` | `group_vars/identity/vault.yml` | `ADMIN_TOKEN` in `.env` (argon hash) |
| `vault_vaultwarden_admin_password` | `group_vars/identity/vault.yml` | Plaintext admin-page password; no role reads it, the role only uses its hash |
| `vault_authentik_vaultwarden_client_secret` | `group_vars/identity/vault.yml` | `SSO_CLIENT_SECRET`; the same value is set on the Authentik provider (see [authentik.md](authentik.md)) |

## How it works

Caddy terminates TLS for `vault.example.com` and proxies to `vaultwarden.example.com:8000` (an A record Terraform writes for VM 303). There is no forward auth in front of it: Vaultwarden speaks OIDC itself.

The login screen offers the normal master-password login and an SSO login. The SSO login redirects to the Authentik provider `vaultwarden`, which authenticates the user against FreeIPA (see [authentik.md](authentik.md#sso-coverage)). A user still needs their master password to unlock the vault after SSO.

## Operations

- **Deploy / rebuild:** from `ansible/`, `ansible-playbook playbooks/identity.yml`. This also runs FreeIPA, Authentik and Caddy; for Vaultwarden alone add `--limit vaultwarden`.
- **Verify:** the role waits for `http://127.0.0.1:8000/alive` (up to 30 tries, 5 s apart). Uptime Kuma checks `http://10.0.0.33:8000/alive` and `https://vault.example.com/alive`, plus a ping of the VM.
- **Recovery:** user data is in `/opt/vaultwarden/data`; restore that directory and re-run the playbook.
