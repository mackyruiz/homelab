# yarr media stack

The `yarr` VM runs one Docker Compose project with Plex, the \*arr apps, qBittorrent behind a VPN, FlareSolverr, Homarr and Watchtower.

| | |
|---|---|
| Host | VM 107 `yarr` (Ubuntu 24.04), 4 cores, 32768 MB RAM, DHCP lease 10.0.0.160 |
| Address / URL | 10.0.0.160; web apps at `https://<app>.example.com` through [Caddy](caddy.md) |
| Ports | 22, 32400 (Plex), 8191 (FlareSolverr), 7575 (Homarr); 8989, 7878, 9696, 8080 only from Caddy and local containers; 6881 tcp/udp (via Gluetun) |
| Software | Docker Compose project `yarr`; all images use `:latest` (see container table) |
| Data | `/opt/yarr` (compose, `.env`, `config/<app>`); NFS media on `/srv/media` |
| Deployed by | `ansible/playbooks/yarr.yml`: roles `common`, `docker`, `nfs_mount`, `internal_dns`, `yarr_stack`; VM from `module.yarr_vm` in `terraform/proxmox/main.tf` |
| Depends on | [Proxmox](proxmox.md), [host baseline](host-baseline.md), [NAS storage](nas-storage.md), [Caddy](caddy.md), [Authentik](authentik.md), [bind9](bind9.md) |
| Used by | [Uptime Kuma](uptime-kuma.md) (monitors and push timer) |

## Purpose

Hosts the media automation and playback services. Each app has its own page; this page covers what they share: the compose project, storage, firewall, secrets and deployment order.

## Configuration

### Files

| Path | What it sets |
|---|---|
| `ansible/playbooks/yarr.yml` | Applies `common`, `docker`, `nfs_mount`, `internal_dns`, `yarr_stack` to the `yarr` host |
| `ansible/roles/yarr_stack/templates/docker-compose.yml.j2` | The nine containers, images, ports and volumes |
| `ansible/roles/yarr_stack/templates/env.j2` | `/opt/yarr/.env` (mode 0600) |
| `ansible/roles/yarr_stack/tasks/main.yml` | Directories, `.env`, compose, start, Homarr admin group, qBittorrent password |
| `ansible/roles/yarr_stack/tasks/sso_firewall.yml` | Locks the forward-auth app ports to Caddy |
| `ansible/roles/yarr_stack/tasks/kuma_push.yml`, `templates/kuma-push.sh.j2`, `files/kuma-push.{service,timer}` | Uptime Kuma push timer |
| `ansible/roles/yarr_stack/files/homarr-seed-admin-group.js` | Homarr admin group, see [Homarr](homarr.md) |
| `ansible/roles/yarr_stack/defaults/main.yml` | qBittorrent login helper facts |
| `ansible/inventory/group_vars/yarr/main.yml` | Paths, ports, VPN, Watchtower, NFS and firewall settings |
| `terraform/proxmox/main.tf` (`module.yarr_vm`) | VM 107 |

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `docker_config_dir` | `group_vars/yarr/main.yml` | `/opt/yarr` |
| `docker_compose_project_name` | `group_vars/yarr/main.yml` | `yarr` |
| `docker_stack_state` | `group_vars/yarr/main.yml` | `present` |
| `media_user_uid` / `media_group_gid` | `group_vars/yarr/main.yml` | 1000 / 1000 (`PUID` / `PGID`) |
| `media_root`, `media_movies_path`, `media_tv_path`, `media_downloads_path` | `group_vars/yarr/main.yml` | `/srv/media`, `/srv/media/Movies`, `/srv/media/tv`, `/srv/media/downloads` |
| `nfs_mount_src`, `nfs_mounts` | `group_vars/yarr/main.yml` | `10.0.0.225:/tank/plex` on `/srv/media` with `x-systemd.automount` |
| `gluetun_enabled`, `gluetun_vpn_service_provider`, `gluetun_vpn_type`, `gluetun_server_countries` | `group_vars/yarr/main.yml` | `true`, `protonvpn`, `wireguard`, `United States` |
| `watchtower_enabled`, `watchtower_schedule` | `group_vars/yarr/main.yml` | `true`, `0 0 4 * * *` |
| `sonarr_port`, `radarr_port`, `prowlarr_port`, `flaresolverr_port`, `plex_port`, `homarr_port`, `qbittorrent_webui_port` | `group_vars/yarr/main.yml` | 8989, 7878, 9696, 8191, 32400, 7575, 8080 |
| `firewall_allowed_tcp_ports` | `group_vars/yarr/main.yml` | 22, 32400, 8191, 7575 |
| `yarr_sso_proxy_ip` | `group_vars/yarr/main.yml` | Caddy's `ansible_host` (10.0.0.34) |
| `yarr_sso_locked_ports` | `group_vars/yarr/main.yml` | Ports of `yarr_forward_auth_apps` (8989, 7878, 9696, 8080) |
| `yarr_docker_bridge_cidr` | `group_vars/yarr/main.yml` | `172.16.0.0/12` |
| `yarr_kuma_push_containers` | `group_vars/yarr/main.yml` | `gluetun`, `watchtower` and their push-token variables |
| `plex_claim_token`, `plex_advertise_url`, `plex_published_server_url` | `group_vars/yarr/main.yml` | Empty by default |
| `yarr_forward_auth_apps` | `group_vars/all/main.yml` | Sonarr, Radarr, Prowlarr, qBittorrent: slug, FQDN, port variable, `health_path` |

### Secrets

Variables in `ansible/inventory/group_vars/yarr/vault.yml` and the `/opt/yarr/.env` key each feeds:

| `.env` key                         | Vault variable                                                |
|------------------------------------|---------------------------------------------------------------|
| `HOMARR_SECRET_ENCRYPTION_KEY`     | `vault_homarr_secret_encryption_key` (`openssl rand -hex 32`) |
| `WIREGUARD_PRIVATE_KEY`            | `vault_gluetun_wireguard_private_key`                         |
| `WIREGUARD_ADDRESSES`              | `vault_gluetun_wireguard_addresses`                           |
| `OPENVPN_USER`                     | `vault_gluetun_openvpn_user`                                  |
| `OPENVPN_PASSWORD`                 | `vault_gluetun_openvpn_password`                              |
| `PLEX_CLAIM`                       | `vault_plex_claim_token`                                      |
| `WATCHTOWER_NOTIFICATION_URL`      | `vault_watchtower_notification_url`                           |
| (qBittorrent Web UI, user `admin`) | `vault_qbittorrent_webui_password`                            |

Create the file only on a new setup: `ansible-vault create inventory/group_vars/yarr/vault.yml`.

Also read by this role, from other vaults:

- `HOMARR_OIDC_CLIENT_SECRET` comes from `vault_authentik_homarr_client_secret` in `group_vars/identity/vault.yml`, read through `hostvars` of the Authentik host.
- The push tokens `vault_uptime_kuma_push_token_gluetun` and `vault_uptime_kuma_push_token_watchtower` live in `group_vars/uptime_kuma_servers/vault.yml` (see [Uptime Kuma](uptime-kuma.md)).

## How it works

### Containers

| Container | Image | Port(s) | Doc |
|---|---|---|---|
| plex | `lscr.io/linuxserver/plex:latest` | 32400 (host network) | [plex.md](plex.md) |
| sonarr | `lscr.io/linuxserver/sonarr:latest` | 8989 | [arr-apps.md](arr-apps.md) |
| radarr | `lscr.io/linuxserver/radarr:latest` | 7878 | [arr-apps.md](arr-apps.md) |
| prowlarr | `lscr.io/linuxserver/prowlarr:latest` | 9696 | [arr-apps.md](arr-apps.md) |
| qbittorrent | `lscr.io/linuxserver/qbittorrent:latest` | 8080 and 6881 via gluetun | [qbittorrent-gluetun.md](qbittorrent-gluetun.md) |
| gluetun | `qmcgaw/gluetun:latest` | 8080, 6881 tcp/udp | [qbittorrent-gluetun.md](qbittorrent-gluetun.md) |
| flaresolverr | `ghcr.io/flaresolverr/flaresolverr:latest` | 8191 | this page |
| homarr | `ghcr.io/homarr-labs/homarr:latest` | 7575 | [homarr.md](homarr.md) |
| watchtower | `nickfedor/watchtower:latest` | none | this page |

Per-app config lives in `/opt/yarr/config/<app>` (`plex`, `qbittorrent`, `sonarr`, `radarr`, `prowlarr`, `gluetun`, `homarr`).

### Storage

NFS `10.0.0.225:/tank/plex` is mounted on `/srv/media` (see [NAS storage](nas-storage.md)) with `Movies`, `tv` and `downloads` directories, which the role creates if missing.

### FlareSolverr

FlareSolverr listens on 8191 and is reached from Prowlarr at `http://flaresolverr:8191`. Uptime Kuma checks it with a keyword monitor for "FlareSolverr is ready".

### Watchtower

Every image uses `:latest`, so Watchtower is the update mechanism. It runs on the schedule `0 0 4 * * *` (daily at 04:00), removes old images (`WATCHTOWER_CLEANUP`) and includes restarting containers. An optional notification URL comes from `vault_watchtower_notification_url`. Its health is pushed to Uptime Kuma (push monitor).

### Firewall

- UFW (from `common`) opens 22, 32400, 8191 and 7575.
- `sso_firewall.yml` removes the open-to-anyone rules for the forward-auth app ports (8989, 7878, 9696, 8080), then allows them only from Caddy's IP and from `172.16.0.0/12` (local containers).
- Docker-published IPv4 ports bypass UFW (FORWARD path), so the role also writes a `DOCKER-USER` drop rule per port into `/etc/ufw/after.rules` for traffic not from Caddy, and reloads UFW when it changes.

### Role order

`yarr_stack/tasks/main.yml` runs:

1. Directories (`/opt/yarr`, `config/*`, media directories on NFS).
2. `.env` (mode 0600).
3. `docker-compose.yml`.
4. SSO firewall.
5. `docker compose up`.
6. Uptime Kuma push timer: `kuma-push.timer` runs `/usr/local/sbin/kuma-push` every minute (see [Uptime Kuma](uptime-kuma.md)).
7. Homarr admin group.
8. qBittorrent password and auth bypass (tag `qbittorrent_password`).

## Operations

Deploy or rebuild, from `ansible/`:

```bash
ansible-playbook playbooks/yarr.yml
```

Dry run:

```bash
ansible-playbook playbooks/yarr.yml --check --diff --skip-tags qbittorrent_password
```

`--skip-tags qbittorrent_password` is needed in check mode because the `uri` tasks cannot run.

Verify: `ssh labadmin@10.0.0.160 docker ps` shows the nine containers; the yarr monitors in [Uptime Kuma](uptime-kuma.md) are up. At the 2026-11-01 deployment, `docker ps` on the host listed exactly these nine containers with the images above.

Recovery: rerun `yarr.yml`; compose state and `/opt/yarr/config/<app>` persist on the VM. After a rebuild see the per-app pages for what is not restored ([Homarr](homarr.md), [arr apps](arr-apps.md)).

Known gaps:

- Images are `:latest`, so a rebuild or Watchtower run can change versions without a repo change.
