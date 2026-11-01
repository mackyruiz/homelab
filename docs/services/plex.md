# Plex

Plex Media Server streams the media library from the yarr VM, with hardware transcoding.

| | |
|---|---|
| Host | VM 107 `yarr` |
| Address / URL | `http://10.0.0.160:32400` |
| Ports | 32400 (host network) |
| Software | `lscr.io/linuxserver/plex:latest` |
| Data | `/opt/yarr/config/plex` (config); media on `/srv/media` |
| Deployed by | `ansible/playbooks/yarr.yml`: role `yarr_stack` |
| Depends on | [yarr stack](yarr-stack.md), [NAS storage](nas-storage.md) |
| Used by | [Uptime Kuma](uptime-kuma.md) |

## Purpose

Plays the Movies and TV libraries stored on the NAS share. It is not fronted by Caddy or SSO; Plex authenticates against plex.tv. See the SSO table in [authentik.md](authentik.md#sso-coverage).

## Configuration

### Files

| Path | What it sets |
|---|---|
| `ansible/roles/yarr_stack/templates/docker-compose.yml.j2` | Container, host networking, devices and volumes |
| `ansible/roles/yarr_stack/templates/env.j2` | `PLEX_CLAIM`, `PLEX_ADVERTISE_URL`, `PLEX_PUBLISHED_SERVER_URL` |
| `ansible/inventory/group_vars/yarr/main.yml` | Plex port and claim/advertise defaults |

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `plex_port` | `group_vars/yarr/main.yml` | 32400; opened in UFW through `firewall_allowed_tcp_ports` |
| `plex_claim_token` | `group_vars/yarr/main.yml` | Empty; fallback for `PLEX_CLAIM` |
| `plex_advertise_url` | `group_vars/yarr/main.yml` | Empty; `ADVERTISE_IP` |
| `plex_published_server_url` | `group_vars/yarr/main.yml` | Empty; written to `.env` as `PLEX_PUBLISHED_SERVER_URL` |

### Secrets

| Vault variable | Vault file | Used for |
|---|---|---|
| `vault_plex_claim_token` | `group_vars/yarr/vault.yml` | `PLEX_CLAIM`; falls back to `plex_claim_token` (empty) when unset |

## How it works

- `network_mode: host`, so Plex listens on 32400 on the VM itself.
- Volumes: `/opt/yarr/config/plex` as `/config`, `/srv/media/Movies` as `/movies`, `/srv/media/tv` as `/tv`, `/srv/media/downloads` as `/downloads`.
- `/dev/dri` is passed through for hardware transcoding and `/dev/shm` is mounted as `/transcode`.
- Uptime Kuma checks `http://10.0.0.160:32400/identity`.

## Operations

Deploy: `ansible-playbook playbooks/yarr.yml` from `ansible/` (see [yarr stack](yarr-stack.md)).

Verify: open `http://10.0.0.160:32400/web`, or check that the Plex monitor in Uptime Kuma is up.

Plex is left unclaimed so you can claim it from its web UI.
