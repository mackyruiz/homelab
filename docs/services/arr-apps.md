# Sonarr, Radarr and Prowlarr

The three *arr apps on the yarr VM: Sonarr (TV), Radarr (movies) and Prowlarr (indexer manager), published only through Caddy with Authentik forward auth.

| | |
|---|---|
| Host | yarr VM 107 (10.0.0.160), see [yarr-stack.md](yarr-stack.md) |
| Address / URL | `https://sonarr.example.com`, `https://radarr.example.com`, `https://prowlarr.example.com` |
| Ports | Sonarr 8989, Radarr 7878, Prowlarr 9696 (direct access firewalled) |
| Software | `lscr.io/linuxserver/sonarr:latest`, `lscr.io/linuxserver/radarr:latest`, `lscr.io/linuxserver/prowlarr:latest` |
| Data | `/opt/yarr/config/{sonarr,radarr,prowlarr}` (config and app SQLite DB); media on `/srv/media` (NFS) |
| Deployed by | `ansible/playbooks/yarr.yml`, role `yarr_stack` |
| Depends on | [yarr-stack.md](yarr-stack.md), [caddy.md](caddy.md), [authentik.md](authentik.md), [nas-storage.md](nas-storage.md), [qbittorrent-gluetun.md](qbittorrent-gluetun.md) |
| Used by | [uptime-kuma.md](uptime-kuma.md) (health checks), [homarr.md](homarr.md) |

## Purpose

Sonarr and Radarr manage the TV and movie libraries and hand downloads to qBittorrent. Prowlarr holds the indexers and syncs them to both. Prowlarr reaches FlareSolverr at `http://flaresolverr:8191` (see [yarr-stack.md](yarr-stack.md)).

## Configuration

### Files

| Path | What it sets |
|---|---|
| [`yarr_stack/templates/docker-compose.yml.j2`](../../ansible/roles/yarr_stack/templates/docker-compose.yml.j2) | Images, ports, volumes, `<APP>__AUTH__METHOD=External` |
| [`yarr_stack/tasks/sso_firewall.yml`](../../ansible/roles/yarr_stack/tasks/sso_firewall.yml) | UFW rules and the `DOCKER-USER` drop rule for the app ports |
| [`inventory/group_vars/all/main.yml`](../../ansible/inventory/group_vars/all/main.yml) | `yarr_forward_auth_apps` |
| [`authentik/templates/blueprints/yarr.yaml.j2`](../../ansible/roles/authentik/templates/blueprints/yarr.yaml.j2) | One `forward_single` proxy provider per app and the embedded outpost |
| [`caddy/templates/Caddyfile.j2`](../../ansible/roles/caddy/templates/Caddyfile.j2) | One site per app, with `authentik_forward_auth` |

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `yarr_forward_auth_apps` | `group_vars/all/main.yml` | Per app: `slug`, `name`, `fqdn`, `port_var`, `health_path`. Sonarr, Radarr and Prowlarr use `/ping`; qBittorrent uses `/api/v2/app/version` |
| `sonarr_port`, `radarr_port`, `prowlarr_port` | yarr role/group vars | Host ports 8989, 7878, 9696 |
| `yarr_sso_proxy_ip` | `group_vars/yarr/main.yml` | Caddy's `ansible_host`; the only outside source allowed to reach the locked ports |
| `yarr_sso_locked_ports` | `group_vars/yarr/main.yml` | Ports of every `yarr_forward_auth_apps` entry |
| `media_tv_path`, `media_movies_path`, `media_downloads_path` | yarr vars | Media locations on `/srv/media` |

### Secrets

None. The apps have no login of their own (`External` auth); the Authentik proxy providers use the shared outpost, see [authentik.md](authentik.md).

### Manual steps

Indexers, the download client and root folders are set in each app's UI. They persist in `/opt/yarr/config/<app>` (the app's SQLite DB) and are not rebuilt from code, so a rebuilt VM without that directory needs them entered again.

- **Download client:** configured in the app UI for Sonarr and Radarr. The host could not be read from the apps' databases: `sqlite3` is not installed on the yarr VM (`sqlite3: command not found`), so the host:port is not recorded here.
- Prowlarr: add the indexers, set FlareSolverr to `http://flaresolverr:8191`, and connect Sonarr and Radarr as apps.
- Sonarr and Radarr: add root folders (`/tv`, `/movies`) and the qBittorrent download client.

## How it works

- Each app runs with `SONARR__AUTH__METHOD`, `RADARR__AUTH__METHOD` or `PROWLARR__AUTH__METHOD` set to `External`: the app trusts whatever sits in front of it.
- Sonarr, Radarr, Prowlarr and qBittorrent are published only as `https://<app>.example.com` through Caddy and Authentik forward auth (`yarr_forward_auth_apps`). `yarr_stack/tasks/sso_firewall.yml` drops direct LAN/IPv6 access to their ports except from Caddy and local containers. Docker-published IPv4 ports bypass UFW, so the role also writes a `DOCKER-USER` drop rule in `/etc/ufw/after.rules`.
- Volumes: Sonarr mounts `/tv` and `/downloads`; Radarr mounts `/movies` and `/downloads`; Prowlarr mounts config only.
- `/ping` is reachable without login (Authentik `skip_path_regex`), so Uptime Kuma can probe the apps. Forward-auth flow: [caddy.md](caddy.md).

## Operations

Deploy: `cd ansible && ansible-playbook playbooks/yarr.yml`. Verify: `https://<app>.example.com/ping` answers without login; the app UIs redirect to Authentik. Container updates come from Watchtower ([yarr-stack.md](yarr-stack.md)).

Recovery: restore `/opt/yarr/config/<app>`, or redo the [manual steps](#manual-steps).

Known gaps:

- Mobile apps or API clients that reach Sonarr/Radarr/Prowlarr/qBittorrent through the HTTPS names are stopped by forward auth, except each app's `health_path` (`yarr_forward_auth_apps`; Authentik `skip_path_regex`, anchored) which Uptime Kuma uses.
